import argparse
import asyncio
import dataclasses
import multiprocessing
import os
import subprocess
import sys
from typing import List, Optional


@dataclasses.dataclass
class ClangTidyResult:
    """
    Class that represents clang-tidy's execution results.
    """

    file_name: str
    ret_code: int
    stdout: str
    stderr: str


def _create_clang_tidy_task_arg_list(file: str, clang_tidy_args: List[str]) -> List[str]:
    """
    :param file: The file to check.
    :param clang_tidy_args: The clang-tidy cli arguments.
    :return: A list of arguments to run clang-tidy to check the given file with the given args.
    """
    args: List[str] = ["clang-tidy", file]
    args.extend(clang_tidy_args)
    # Enforce `warning-as-error` for all checks:
    args.append("-warnings-as-errors=*")
    return args


def _collect_target_files(input_paths: List[str]) -> List[str]:
    """
    Collect all the target files to lint, including all C++ source/header files under the input
    directory.

    :param input_paths: The input paths.
    :return: A list of target files.
    """
    target_files = []
    for path in input_paths:
        if os.path.isfile(path):
            target_files.append(os.path.abspath(path))
            continue
        if not os.path.isdir(path):
            continue
        for root, _, files in os.walk(path):
            for name in files:
                if name.endswith('.cpp') or name.endswith('.hpp'):
                    full_path = os.path.join(root, name)
                    target_files.append(os.path.abspath(full_path))
    return target_files


async def _execute_clang_tidy_task(file: str, clang_tidy_args: List[str]) -> ClangTidyResult:
    """
    Executes a single clang-tidy task by checking one file using a process managed by asyncio.

    :param file: The file to check.
    :param clang_tidy_args: The clang-tidy cli arguments.
    :return: Execution results represented by an instance of `ClangTidyResult`.
    """
    task_args: List[str] = _create_clang_tidy_task_arg_list(file, clang_tidy_args)
    try:
        process = await asyncio.create_subprocess_exec(
            *task_args, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        stdout, stderr = await process.communicate()
    except asyncio.CancelledError:
        process.terminate()
        await process.wait()
        raise

    assert process.returncode is not None
    return ClangTidyResult(
        file,
        process.returncode,
        stdout.decode("UTF-8"),
        stderr.decode("UTF-8"),
    )


async def _execute_clang_tidy_task_with_sem(
    sem: asyncio.Semaphore, file: str, clang_tidy_args: List[str]
) -> ClangTidyResult:
    """
    Wrapper of `execute_clang_tidy_task` with a global semaphore for concurrency control.

    :param sem: The global semaphore for concurrency control.
    :param file: The file to check.
    :param clang_tidy_args: The clang-tidy cli arguments.
    :return: Forwards `execute_clang_tidy_task`'s return values.
    """
    async with sem:
        return await _execute_clang_tidy_task(file, clang_tidy_args)


async def _clang_tidy_parallel_execution_entry(
    num_jobs: int,
    files: List[str],
    clang_tidy_args: List[str],
) -> int:
    """
    Async entry for running clang-tidy checks in parallel.

    :param num_jobs: The maximum number of jobs allowed to run in parallel.
    :param files: The list of files to check.
    :param clang_tidy_args: The clang-tidy cli arguments.
    """
    sem: asyncio.Semaphore = asyncio.Semaphore(num_jobs)
    tasks: List[asyncio.Task[ClangTidyResult]] = [
        asyncio.create_task(_execute_clang_tidy_task_with_sem(sem, file, clang_tidy_args))
        for file in files
    ]
    num_total_files: int = len(files)

    ret_code: int = 0
    try:
        for idx, clang_tidy_task in enumerate(asyncio.as_completed(tasks)):
            result: ClangTidyResult = await clang_tidy_task
            if 0 != result.ret_code:
                ret_code = 1
                print(f"[{idx + 1}/{num_total_files}]: {result.file_name}")
                print(result.stdout)
                print(result.stderr)
            else:
                print(f"[{idx + 1}/{num_total_files}]: {result.file_name} [All check passed!]")
    except asyncio.CancelledError as e:
        print(f"\nAll tasks cancelled: {e}")
        for task in tasks:
            task.cancel()

    return ret_code


def main() -> None:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="clang-tidy-utils cli options.",
    )

    parser.add_argument(
        "-j",
        "--num-jobs",
        type=int,
        help="Number of jobs to run for parallel processing.",
    )

    parser.add_argument(
        "input_files",
        metavar="FILE",
        type=str,
        nargs="+",
        help="Input files to process.",
    )

    default_parser_usage: str = parser.format_usage()
    if default_parser_usage.endswith("\n"):
        default_parser_usage = default_parser_usage[:-1]
    usage_prefix: str = "usage: "
    if default_parser_usage.startswith(usage_prefix):
        default_parser_usage = default_parser_usage[len(usage_prefix) :]
    usage: str = default_parser_usage + " [-- CLANG-TIDY-ARGS ...]"
    parser.usage = usage

    args: List[str] = sys.argv[1:]
    delimiter_idx: Optional[int] = None
    try:
        delimiter_idx = args.index("--")
    except ValueError:
        pass

    cli_args: List[str] = args
    clang_tidy_args: List[str] = []
    if delimiter_idx is not None:
        cli_args = args[:delimiter_idx]
        clang_tidy_args = args[delimiter_idx + 1 :]

    parsed_cli_args: argparse.Namespace = parser.parse_args(cli_args)

    num_jobs: int
    if parsed_cli_args.num_jobs is not None:
        num_jobs = parsed_cli_args.num_jobs
    else:
        num_jobs = multiprocessing.cpu_count()

    ret_code: int = 0
    try:
        ret_code = asyncio.run(
            _clang_tidy_parallel_execution_entry(
                num_jobs, _collect_target_files(parsed_cli_args.input_files), clang_tidy_args
            )
        )
    except KeyboardInterrupt:
        pass

    if 0 != ret_code:
        # Ideally, we should return the error code directly. However, this utility is used inside
        # the GitHub action, and we don't want to fail the workflow. We log the error code instead
        # if it's not 0.
        print(f"\nclang-tidy-utils: Linter check failed with return code {ret_code}")

    exit(0)


if "__main__" == __name__:
    main()

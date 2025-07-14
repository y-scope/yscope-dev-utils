#include <chrono>
#include <exception>
#include <future>
#include <iostream>
#include <string>
#include <string_view>

#include <boost/any.hpp>
#include <boost/asio.hpp>
#include <boost/dll/runtime_symbol_info.hpp>
#include <boost/filesystem.hpp>
#include <boost/iostreams/device/back_inserter.hpp>
#include <boost/iostreams/filtering_stream.hpp>
#include <boost/process/v2.hpp>
#include <boost/process/v2/stdio.hpp>
#include <boost/program_options.hpp>
#include <boost/regex.hpp>
#include <boost/system.hpp>
#include <boost/url.hpp>

namespace {
constexpr int cCmdArgParseErr = 1;
constexpr int cSizeErr = 2;
constexpr int cFileSystemErr = 3;
constexpr int cIoStreamsErr = 4;
constexpr int cProcessErr = 5;
constexpr int cRegexErr = 6;
constexpr int cUrlErr = 7;

auto run_tests(boost::program_options::variables_map const& args) -> int;
auto test_filesystem() -> bool;
auto test_iostreams() -> bool;
auto test_process() -> bool;
auto test_regex() -> bool;
auto test_url() -> bool;

auto run_tests(boost::program_options::variables_map const& args) -> int {
    std::string input;
    int size = 0;
    try {
        input = args["input"].as<std::string>();
        size = args["size"].as<int>();
    } catch (boost::bad_any_cast const& e) {
        std::cerr << "Error: Bad any cast: " << e.what() << "\n";
        return cCmdArgParseErr;
    }

    if (size != input.size()) {
        std::cerr << "Error: Size mismatch. Expected size: " << size
                  << ", actual string length: " << input.size() << ".\n";
        return cSizeErr;
    }

    if (false == test_filesystem()) {
        std::cerr << "Error: Filesystem test failed. Could not verify parent path.\n";
        return cFileSystemErr;
    }

    if (false == test_iostreams()) {
        std::cerr << "Error: IoStreams test failed. Could not write and verify string.\n";
        return cIoStreamsErr;
    }

    if (false == test_process()) {
        std::cerr << "Error: Process test failed. Could not execute process or verify exit code.\n";
        return cProcessErr;
    }

    if (false == test_regex()) {
        std::cerr << "Error: Regex test failed. Could not match pattern.\n";
        return cRegexErr;
    }

    if (false == test_url()) {
        std::cerr << "Error: URL test failed. Could not parse URL or verify host.\n";
        return cUrlErr;
    }

    return 0;
}

auto test_filesystem() -> bool {
    boost::filesystem::path const path = boost::filesystem::path(__FILE__);
    return path.has_parent_path();
}

auto test_iostreams() -> bool {
    std::string result;
    try {
        boost::iostreams::filtering_ostream out{boost::iostreams::back_inserter(result)};
        out << "Hello World!";
        out.flush();
    } catch (std::exception const& e) {
        return false;
    }
    return result == "Hello World!";
}

auto test_process() -> bool {
    constexpr int cWaitTime = 10;
    try {
        boost::asio::io_context io_context;
        boost::filesystem::path const test_boost = boost::dll::program_location();
        boost::process::v2::process process{
                io_context,
                test_boost,
                {"--help"},
                boost::process::process_stdio{.in{}, .out{nullptr}, .err{nullptr}}
        };
        std::future<int> result = process.async_wait(boost::asio::use_future);
        io_context.run_for(std::chrono::milliseconds(cWaitTime));
        if (std::future_status::ready != result.wait_for(std::chrono::milliseconds(cWaitTime))) {
            return false;
        }
        return 0 == result.get();
    } catch (std::exception const& e) {
        return false;
    }
}

auto test_regex() -> bool {
    constexpr std::string_view cRegex = "(\\d{4}[- ]){3}\\d{4}";
    constexpr std::string_view cMatch = "1234-5678 9012-3456";
    try {
        boost::regex const e{std::string{cRegex}};
        // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange)
        return boost::regex_match(std::string{cMatch}, e);
    } catch (std::exception const& e) {
        return false;
    }
}

auto test_url() -> bool {
    constexpr std::string_view cUrl
            = "https://user:pass@example.com:443/path/to/"
              "my%2dfile.txt?id=42&name=John%20Doe+Jingleheimer%2DSchmidt#page%20anchor";
    boost::system::result<boost::urls::url_view> result = boost::urls::parse_uri(cUrl);
    if (result.has_error()) {
        return false;
    }
    boost::urls::url_view const url_view = result.value();
    return "example.com" == url_view.encoded_host_address();
}
}  // namespace

auto main(int argc, char** argv) -> int {
    boost::program_options::options_description desc{"Possible options"};
    desc.add_options()
        ("help", "Print help message.")
        ("input", boost::program_options::value<std::string>()->required(), "Input string.")
        (
             "size",
             boost::program_options::value<int>()->required(),
             "Size to test input string against."
        )
    ;

    boost::program_options::variables_map variables;
    try {
        boost::program_options::store(
                boost::program_options::parse_command_line(argc, argv, desc),
                variables
        );

        if (variables.contains("help")) {
            std::cerr << desc << "\n";
            return 0;
        }

        boost::program_options::notify(variables);
    } catch (boost::program_options::error const& e) {
        std::cerr << "Error: Program options error: " << e.what() << "\n";
        return cCmdArgParseErr;
    }

    return run_tests(variables);
}

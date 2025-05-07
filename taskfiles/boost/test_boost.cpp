#include <chrono>
#include <exception>
#include <future>
#include <iostream>
#include <string>
#include <string_view>

#include <boost/any.hpp>
#include <boost/asio.hpp>
#include <boost/filesystem.hpp>
#include <boost/iostreams/device/back_inserter.hpp>
#include <boost/iostreams/filtering_stream.hpp>
#include <boost/process/v2.hpp>
#include <boost/program_options.hpp>
#include <boost/regex.hpp>
#include <boost/system.hpp>
#include <boost/url.hpp>

namespace {
auto parse_args(int argc, char** argv) -> boost::program_options::variables_map {
    boost::program_options::options_description desc;
    desc.add_options()("help", "Boost task test. Check the string against its size.");
    desc.add_options()("input", boost::program_options::value<std::string>(), "Input string.");
    desc.add_options()("size", boost::program_options::value<int>(), "Size of the string.");
    boost::program_options::variables_map variables;
    boost::program_options::store(
            boost::program_options::parse_command_line(argc, argv, desc),
            variables
    );
    boost::program_options::notify(variables);
    return variables;
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

constexpr int cWaitTime = 10;

auto test_process() -> bool {
    try {
        boost::asio::io_context io_context;
        boost::process::v2::process process{io_context, "/bin/true", {}};
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

constexpr std::string_view cRegex = "(\\d{4}[- ]){3}\\d{4}";
constexpr std::string_view cMatch = "1234-5678 9012-3456";

auto test_regex() -> bool {
    try {
        boost::regex const e{std::string{cRegex}};
        // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange)
        return boost::regex_match(std::string{cMatch}, e);
    } catch (std::exception const& e) {
        return false;
    }
}

constexpr std::string_view cUrl
        = "https://user:pass@example.com:443/path/to/"
          "my%2dfile.txt?id=42&name=John%20Doe+Jingleheimer%2DSchmidt#page%20anchor";

auto test_url() -> bool {
    boost::system::result<boost::urls::url_view> result = boost::urls::parse_uri(cUrl);
    if (result.has_error()) {
        return false;
    }
    boost::urls::url_view const url_view = result.value();
    return "example.com" == url_view.encoded_host_address();
}

constexpr int cCmdArgParseErr = 1;
constexpr int cSizeErr = 2;
constexpr int cFileSystemErr = 3;
constexpr int cIoStreamsErr = 4;
constexpr int cProcessErr = 5;
constexpr int cRegexErr = 6;
constexpr int cUrlErr = 7;
}  // namespace

auto main(int argc, char** argv) -> int {
    boost::program_options::variables_map const args = parse_args(argc, argv);

    std::string input;
    int size = 0;

    try {
        if (false == args.contains("input")) {
            std::cerr << "Error: Missing input argument.\n";
            return cCmdArgParseErr;
        }
        input = args["input"].as<std::string>();
        if (false == args.contains("size")) {
            std::cerr << "Error: Missing size argument.\n";
            return cCmdArgParseErr;
        }
        size = args["size"].as<int>();
    } catch (boost::bad_any_cast const& e) {
        std::cerr << "Error: Bad any cast: " << e.what() << "\n";
        return cCmdArgParseErr;
    } catch (boost::program_options::error const& e) {
        std::cerr << "Error: Program options error: " << e.what() << "\n";
        return cCmdArgParseErr;
    }

    if (size != input.size()) {
        std::cerr << "Error: Size mismatch. Expected size: " << size
                  << ", actual string length: " << input.size() << ".\n";
        return cSizeErr;
    }

    if (false == test_filesystem()) {
        return cFileSystemErr;
    }

    if (false == test_iostreams()) {
        return cIoStreamsErr;
    }

    if (false == test_process()) {
        return cProcessErr;
    }

    if (false == test_regex()) {
        return cRegexErr;
    }

    if (false == test_url()) {
        return cUrlErr;
    }

    return 0;
}

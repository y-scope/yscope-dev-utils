
#include <iostream>
#include <string>

#include <boost/program_options/errors.hpp>
#include <boost/program_options/options_description.hpp>
#include <boost/program_options/parsers.hpp>
#include <boost/program_options/value_semantic.hpp>
#include <boost/program_options/variables_map.hpp>

namespace {

auto parse_args(int argc, char** argv) -> boost::program_options::variables_map {
    boost::program_options::options_description desc;
    desc.add_options()("help", "Boost task test. Check the string against its size.");
    desc.add_options()("input", boost::program_options::value<std::string>(), "Input string.");
    desc.add_options()("size", boost::program_options::value<int>(), "Size of the string.");
    boost::program_options::variables_map variables;
    boost::program_options::store(
            // NOLINTNEXTLINE(misc-include-cleaner)
            boost::program_options::parse_command_line(argc, argv, desc),
            variables
    );
    boost::program_options::notify(variables);
    return variables;
}
constexpr int cCmdArgParseErr = 1;
constexpr int cSizeErr = 2;
}

auto main(int argc, char** argv) -> int {
    boost::program_options::variables_map const args = parse_args(argc, argv);

    std::string input;
    int size;

    try {
        if (!args.contains("input")) {
            std::cerr << "Error: Missing input argument.\n";
            return cCmdArgParseErr;
        }
        input = args["input"].as<std::string>();
        if (!args.contains("size")) {
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
        std::cerr << "Error: Size mismatch. Expected " << input.size() << ", got " << size << ".\n";
        return cSizeErr;
    }

    return 0;
}
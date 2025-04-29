cmake_minimum_required(VERSION 3.22.1)

project(boost-test LANGUAGES CXX VERSION 0.1.0)

set(CMAKE_EXPORT_COMPILE_COMMANDS
    ON
    CACHE BOOL
    "Enable/Disable output of compile commands during generation."
    FORCE
)

include("build/deps/cmake-settings/all.cmake")

find_package(
    Boost
    1.83
    REQUIRED
    COMPONENTS
        filesystem
        headers
        iostreams
        process
        program_options
        regex
        system
        url
)
if(Boost_FOUND)
    message(STATUS "Found Boost ${Boost_VERSION}.")
endif()

add_executable(boost-test)
target_compile_features(boost-test PRIVATE cxx_std_20)
target_sources(boost-test PRIVATE boost-test.cpp)
target_link_libraries(
    boost-test
    PRIVATE
        Boost::filesystem
        Boost::headers
        Boost::iostreams
        Boost::process
        Boost::program_options
        Boost::regex
        Boost::system
        Boost::url
)

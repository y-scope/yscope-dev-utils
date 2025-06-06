cmake_minimum_required(VERSION 3.22.1)

project(boost-test LANGUAGES CXX VERSION 0.1.0)

set(CMAKE_EXPORT_COMPILE_COMMANDS
    ON
    CACHE BOOL
    "Enable/Disable output of compile commands during generation."
    FORCE
)

if(PROJECT_IS_TOP_LEVEL)
    # Include dependency settings if the project isn't being included as a subproject.
    # NOTE: We mark the file optional because if the user happens to have the dependencies
    # installed, this file is not necessary.
    include(
        "${CMAKE_CURRENT_SOURCE_DIR}/../../build/deps/cmake-settings/all.cmake"
        OPTIONAL
    )
endif()

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
target_sources(boost-test PRIVATE test_boost.cpp)
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

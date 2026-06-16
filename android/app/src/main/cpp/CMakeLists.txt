cmake_minimum_required(VERSION 3.10.2)
project("termode_pty")

add_library(
    termode_pty
    SHARED
    termode_pty.cpp
)

find_library(
    log-lib
    log
)

target_link_libraries(
    termode_pty
    ${log-lib}
)

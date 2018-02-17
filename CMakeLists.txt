cmake_minimum_required(VERSION 2.8.8)

project(GGJ2018)

set(HARFANG_SDK "D:/harfang/sdk" CACHE STRING "Assemble: Path to the Harfang SDK")

link_directories(${HARFANG_SDK}/lib/${CMAKE_CFG_INTDIR})
include_directories(${HARFANG_SDK}/include)

add_executable(ggj2018 main.cpp)
target_include_directories(ggj2018 PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(ggj2018 engine platform foundation lua53 User32 Gdi32 Ws2_32 Wldap32 Winmm dxguid dinput8 DbgHelp ShCore)

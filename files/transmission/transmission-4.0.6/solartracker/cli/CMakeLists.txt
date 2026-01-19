add_executable(${TR_NAME}-cli)

target_sources(${TR_NAME}-cli
    PRIVATE
        cli.cc)

target_link_libraries(${TR_NAME}-cli
    PRIVATE
        ${LIBTRANSMISSION_LIB}
        ${CMAKE_INSTALL_PREFIX}/lib/libdeflate.a
        ${CMAKE_INSTALL_PREFIX}/lib/libssl.a
        ${CMAKE_INSTALL_PREFIX}/lib/libcrypto.a
        -ldl
        ${CMAKE_INSTALL_PREFIX}/lib/libcurl.a
        ${CMAKE_INSTALL_PREFIX}/lib/libpsl.a
        ${CMAKE_INSTALL_PREFIX}/lib/libnatpmp.a
        ${CMAKE_INSTALL_PREFIX}/lib/libminiupnpc.a
        ${CMAKE_INSTALL_PREFIX}/third-party/dht/libdht.a
        ${CMAKE_INSTALL_PREFIX}/lib/libutp.a
        ${CMAKE_INSTALL_PREFIX}/lib/libb64.a
        -lm
        ${CMAKE_INSTALL_PREFIX}/third-party/jsonsl/libjsonsl.a
        ${CMAKE_INSTALL_PREFIX}/third-party/wildmat/libwildmat.a
        ${TR_NAME}
        fmt::fmt-header-only
)

tr_win32_app_info(${TR_NAME}-cli
    "Transmission Utility ('cli', obsolete)"
    "${TR_NAME}-cli"
    "${TR_NAME}-cli.exe")

install(
    TARGETS ${TR_NAME}-cli
    DESTINATION ${CMAKE_INSTALL_BINDIR})

if(INSTALL_DOC)
    install(
        FILES ${TR_NAME}-cli.1
        DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
endif()

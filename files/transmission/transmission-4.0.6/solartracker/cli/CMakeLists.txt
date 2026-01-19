add_executable(${TR_NAME}-cli)

target_sources(${TR_NAME}-cli
    PRIVATE
        cli.cc)

target_link_libraries(${TR_NAME}-cli
    PRIVATE
        ${LIBTRANSMISSION_LIB}
        ${PREFIX}/lib/libdeflate.a
        ${PREFIX}/lib/libssl.a
        ${PREFIX}/lib/libcrypto.a
        -ldl
        ${PREFIX}/lib/libcurl.a
        ${PREFIX}/lib/libpsl.a
        ${PREFIX}/lib/libnatpmp.a
        ${PREFIX}/lib/libminiupnpc.a
        ${PREFIX}/third-party/dht/libdht.a
        ${PREFIX}/lib/libutp.a
        ${PREFIX}/lib/libb64.a
        -lm
        ${PREFIX}/third-party/jsonsl/libjsonsl.a
        ${PREFIX}/third-party/wildmat/libwildmat.a
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

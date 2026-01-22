add_executable(${TR_NAME}-cli)

target_sources(${TR_NAME}-cli
    PRIVATE
        cli.cc)

target_link_libraries(${TR_NAME}-cli
    PRIVATE
        ${LIBTRANSMISSION_LIB}
        ${TR_NAME}
        ${CMAKE_INSTALL_PREFIX}/lib/libcurl.a
        ${CMAKE_INSTALL_PREFIX}/lib/libz.a
        ${CMAKE_INSTALL_PREFIX}/lib/libzstd.a
        ${CMAKE_INSTALL_PREFIX}/lib/libssl.a
        ${CMAKE_INSTALL_PREFIX}/lib/libcrypto.a
        ${CMAKE_BINARY_DIR}/third-party/libdeflate.bld/pfx/lib/libdeflate.a
        ${CMAKE_BINARY_DIR}/third-party/libpsl.bld/pfx/lib/libpsl.a
        ${CMAKE_BINARY_DIR}/third-party/libnatpmp.bld/pfx/lib/libnatpmp.a
        ${CMAKE_BINARY_DIR}/third-party/miniupnpc.bld/pfx/lib/libminiupnpc.a
        ${CMAKE_BINARY_DIR}/third-party/dht/libdht.a
        ${CMAKE_BINARY_DIR}/third-party/libutp.bld/libutp.a
        ${CMAKE_BINARY_DIR}/third-party/libb64.bld/src/libb64.a
        ${CMAKE_BINARY_DIR}/third-party/jsonsl/libjsonsl.a
        ${CMAKE_BINARY_DIR}/third-party/wildmat/libwildmat.a
        ${CMAKE_INSTALL_PREFIX}/lib/libevent.a
        -lm
        -ldl
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

foreach(P create edit remote show)
    add_executable(${TR_NAME}-${P})

    target_sources(${TR_NAME}-${P}
        PRIVATE
            ${P}.cc)

    target_link_libraries(${TR_NAME}-${P}
        PRIVATE
            ${LIBTRANSMISSION_LIB}
            ${TR_NAME}
            ${CMAKE_INSTALL_PREFIX}/lib/libcurl.a
            ${CMAKE_INSTALL_PREFIX}/lib/libidn2.a
            ${CMAKE_INSTALL_PREFIX}/lib/libz.a
            ${CMAKE_INSTALL_PREFIX}/lib/libzstd.a
            ${CMAKE_INSTALL_PREFIX}/lib/libssl.a
            ${CMAKE_INSTALL_PREFIX}/lib/libcrypto.a
            ${CMAKE_INSTALL_PREFIX}/lib/libdeflate.a
            ${CMAKE_INSTALL_PREFIX}/lib/libpsl.a
            ${CMAKE_INSTALL_PREFIX}/lib/libnatpmp.a
            ${CMAKE_INSTALL_PREFIX}/lib/libminiupnpc.a
            ${CMAKE_BINARY_DIR}/third-party/dht/libdht.a
            ${CMAKE_INSTALL_PREFIX}/lib/libutp.a
            ${CMAKE_INSTALL_PREFIX}/lib/libb64.a
            ${CMAKE_BINARY_DIR}/third-party/jsonsl/libjsonsl.a
            ${CMAKE_BINARY_DIR}/third-party/wildmat/libwildmat.a
            ${CMAKE_INSTALL_PREFIX}/lib/libevent.a
            -lm
            -ldl
    )

    tr_win32_app_info(${TR_NAME}-${P}
        "Transmission Utility ('${P}')"
        "${TR_NAME}-${P}"
        "${TR_NAME}-${P}.exe")

    install(
        TARGETS ${TR_NAME}-${P}
        DESTINATION ${CMAKE_INSTALL_BINDIR})

    if(INSTALL_DOC)
        install(
            FILES ${TR_NAME}-${P}.1
            DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
    endif()
endforeach()

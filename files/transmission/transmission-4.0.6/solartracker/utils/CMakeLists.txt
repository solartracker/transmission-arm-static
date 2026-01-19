foreach(P create edit remote show)
    add_executable(${TR_NAME}-${P})

    target_sources(${TR_NAME}-${P}
        PRIVATE
            ${P}.cc)

    target_link_libraries(${TR_NAME}-${P}
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
            CURL::libcurl
            fmt::fmt-header-only
            libevent::event
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

add_executable(${TR_NAME}-daemon)

target_sources(${TR_NAME}-daemon
    PRIVATE
        daemon.cc
        daemon.h
        daemon-posix.cc
        daemon-win32.cc)

tr_allow_compile_if(
    [=[[WIN32]]=]
        daemon-win32.cc
    [=[[NOT WIN32]]=]
        daemon-posix.cc)

target_compile_definitions(${TR_NAME}-daemon
    PRIVATE
        $<$<BOOL:${WITH_SYSTEMD}>:USE_SYSTEMD>)

tr_target_compile_definitions_for_headers(${TR_NAME}-daemon
    PRIVATE
        sys/signalfd.h)

tr_target_compile_definitions_for_functions(${TR_NAME}-daemon
    PRIVATE
        daemon
        syslog)

target_include_directories(${TR_NAME}-daemon SYSTEM
    PRIVATE
        $<$<BOOL:${WITH_SYSTEMD}>:${SYSTEMD_INCLUDE_DIRS}>)

target_link_libraries(${TR_NAME}-daemon
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
        libevent::event
        fmt::fmt-header-only
        $<$<BOOL:${WITH_SYSTEMD}>:${SYSTEMD_LIBRARIES}>
)

tr_win32_app_info(${TR_NAME}-daemon
    "Transmission Daemon"
    "${TR_NAME}-daemon"
    "${TR_NAME}-daemon.exe")

foreach(P daemon)
    install(
        TARGETS ${TR_NAME}-${P}
        DESTINATION ${CMAKE_INSTALL_BINDIR})

    if(INSTALL_DOC)
        install(
            FILES ${TR_NAME}-${P}.1
            DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
    endif()
endforeach()

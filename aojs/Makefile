# AOJS WASM Build
WASI_SDK_VERSION = 24.0
# WASI_SDK = $(HOME)/wasi-sdk-$(WASI_SDK_VERSION)-x86_64-linux
WASI_SDK = $(HOME)/wasi-sdk-$(WASI_SDK_VERSION)-arm64-macos
SYSROOT = $(WASI_SDK)/share/wasi-sysroot
CC = $(WASI_SDK)/bin/clang
 
QJS_VERSION = 2024-01-13
QJS = $(HOME)/quickjs-$(QJS_VERSION)
 
CFLAGS = \
    --sysroot=$(SYSROOT) \
    --target=wasm32-wasi \
    -O1 \
    -DCONFIG_VERSION=\"$(QJS_VERSION)\" \
    -D_WASI_EMULATED_SIGNAL \
    -D_WASI_EMULATED_PROCESS_CLOCKS \
    -DCONFIG_BIGNUM \
    -include wasi_stubs.h
 
LDFLAGS = \
    --sysroot=$(SYSROOT) \
    --target=wasm32-wasi \
    -Wl,-z,stack-size=1048576 \
    -Wl,--initial-memory=16777216 \
    -Wl,--max-memory=67108864 \
    -Wl,--export=malloc \
    -Wl,--export=free \
    -Wl,--export=qjs_init \
    -Wl,--export=qjs_eval \
    -lwasi-emulated-signal \
    -lwasi-emulated-process-clocks
 
OBJS = ao_runtime.o quickjs.o cutils.o libbf.o libregexp.o libunicode.o
 
all: aojs.wasm
 
aojs.wasm: $(OBJS)
	$(CC) $(LDFLAGS) $^ -o $@
 
ao_runtime.o: ao_runtime.c
	$(CC) $(CFLAGS) -I$(QJS) -c $< -o $@
 
quickjs.o: $(QJS)/quickjs.c
	$(CC) $(CFLAGS) -I$(QJS) -c $< -o $@
 
cutils.o: $(QJS)/cutils.c
	$(CC) $(CFLAGS) -I$(QJS) -c $< -o $@
 
libbf.o: $(QJS)/libbf.c
	$(CC) $(CFLAGS) -I$(QJS) -c $< -o $@
 
libregexp.o: $(QJS)/libregexp.c
	$(CC) $(CFLAGS) -I$(QJS) -c $< -o $@
 
libunicode.o: $(QJS)/libunicode.c
	$(CC) $(CFLAGS) -I$(QJS) -c $< -o $@
 
clean:
	rm -f *.o aojs.wasm
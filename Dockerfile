FROM debian:bullseye-slim as builder
# Install linux dependencies
RUN apt-get update -y && apt-get install -y \
	g++ \
	clang \
	libc++-dev \
	libc++abi-dev \
	cmake \
	ninja-build \
	libx11-dev libxcursor-dev libxi-dev libgl1-mesa-dev libfontconfig1-dev \
	git \
	python3

# Define a path for dependencies download
RUN mkdir /deps
# Define softlink for python
RUN ln -s /usr/bin/python3 /usr/bin/python

FROM builder as gn-builder
WORKDIR /deps
# GN: meta-build system that generates build files for Ninja
# --> Latest binary in case you don't want to compile it: https://chrome-infra-packages.appspot.com/dl/gn/gn/linux-amd64/+/latest
RUN git clone https://gn.googlesource.com/gn
WORKDIR /deps/gn
RUN python build/gen.py
RUN ninja -C out

FROM builder as skia-builder
# Install required linux dependencies
RUN apt-get install -y xz-utils bzip2 lsb-release

# Copy previously compiled binaries to some PATH folder
WORKDIR /deps
#COPY --from=gn-builder /deps/gn/out/gn /usr/local/bin
# Download dependencies source code
RUN git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
## Remember to include the depot_tools in the PATH env!
ENV PATH="/deps/depot_tools:${PATH}"

# Clone the skia source code and compile it
RUN git clone -b aseprite-m102 https://github.com/aseprite/skia.git
WORKDIR /deps/skia
RUN python tools/git-sync-deps

## Generate compilation rules
### Option 1: clang compilation rules (recommended)
RUN gn gen out/Release-x64 --args='is_debug=false is_official_build=true skia_use_system_expat=false skia_use_system_icu=false skia_use_system_libjpeg_turbo=false skia_use_system_libpng=false skia_use_system_libwebp=false skia_use_system_zlib=false skia_use_sfntly=false skia_use_freetype=true skia_use_harfbuzz=true skia_pdf_subset_harfbuzz=true skia_use_system_freetype2=false skia_use_system_harfbuzz=false cc="clang" cxx="clang++" extra_cflags_cc=["-stdlib=libc++"] extra_ldflags=["-stdlib=libc++"]'
### Option 2: default compiler rules (usually g++)
#RUN gn gen out/Release-x64 --args="is_debug=false is_official_build=true skia_use_system_expat=false skia_use_system_icu=false skia_use_system_libjpeg_turbo=false skia_use_system_libpng=false skia_use_system_libwebp=false skia_use_system_zlib=false skia_use_sfntly=false skia_use_freetype=true skia_use_harfbuzz=true skia_pdf_subset_harfbuzz=true skia_use_system_freetype2=false skia_use_system_harfbuzz=false"

## Compile with ninja
RUN ninja -C out/Release-x64 skia modules

# Aseprite builder
FROM builder as aseprite-builder
# Copy compiled Skia
COPY --from=skia-builder /deps/skia /deps/skia
COPY . /aseprite
# Prepare build path
RUN mkdir -p /aseprite/build
WORKDIR /aseprite/build
# Define environment variables
ENV CC=clang
ENV CXX=clang++
# Run cmake
RUN cmake \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_CXX_FLAGS:STRING=-stdlib=libc++ \
  -DCMAKE_EXE_LINKER_FLAGS:STRING=-stdlib=libc++ \
  -DLAF_BACKEND=skia \
  -DSKIA_DIR=/deps/skia \
  -DSKIA_LIBRARY_DIR=/deps/skia/out/Release-x64 \
  -DSKIA_LIBRARY=/deps/skia/out/Release-x64/libskia.a \
  -G Ninja \
  ..
## Compile with ninja
RUN ninja aseprite

# Artifacts export
FROM scratch as artifact
COPY --from=aseprite-builder /aseprite/build/bin /


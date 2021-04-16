FROM debian:stretch-slim

# OS-X SDK parameters
ARG OSX_SDK=MacOSX11.1.sdk
ARG OSX_SDK_SUM=699da1b5df4665ada843ed7625a408226f82671ad193328dd30f52a46f5b38bc

ENV OSX_CROSS_PATH=/osxcross

COPY ${OSX_SDK}.tar.xz "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz"
RUN echo "${OSX_SDK_SUM}"  "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz" | sha256sum -c -
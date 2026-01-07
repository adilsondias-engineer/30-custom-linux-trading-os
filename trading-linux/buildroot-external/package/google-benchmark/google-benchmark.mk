################################################################################
#
# google-benchmark
#
################################################################################

GOOGLE_BENCHMARK_VERSION = $(call qstrip,$(BR2_PACKAGE_GOOGLE_BENCHMARK_VERSION))
ifeq ($(GOOGLE_BENCHMARK_VERSION),)
GOOGLE_BENCHMARK_VERSION = 1.8.3
endif

GOOGLE_BENCHMARK_SITE = $(call github,google,benchmark,v$(GOOGLE_BENCHMARK_VERSION))

GOOGLE_BENCHMARK_LICENSE = Apache-2.0
GOOGLE_BENCHMARK_LICENSE_FILES = LICENSE

GOOGLE_BENCHMARK_INSTALL_STAGING = YES
GOOGLE_BENCHMARK_DEPENDENCIES = \
	host-cmake \
	host-pkgconf

# Google Benchmark CMake options
GOOGLE_BENCHMARK_CONF_OPTS = \
	-DBENCHMARK_ENABLE_TESTING=OFF \
	-DBENCHMARK_ENABLE_INSTALL=ON \
	-DBENCHMARK_ENABLE_GTEST_TESTS=OFF \
	-DCMAKE_BUILD_TYPE=Release

$(eval $(cmake-package))


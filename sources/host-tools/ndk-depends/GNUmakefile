# Copyright (C) 2013, 2017 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# The following variables can be over-ridden by the caller
CC        := gcc
CXX       := g++
STRIP     := strip
BUILD_DIR := /tmp/ndk-$(USER)/build/build-ndk-depends
PROGNAME  := /tmp/ndk-$(USER)/ndk-depends

EXECUTABLE := $(PROGNAME)

all: $(EXECUTABLE)

# The rest should be left alone
EXTRA_CFLAGS := -Wall -Werror -fno-exceptions -fno-rtti
EXTRA_LDFLAGS := -lstdc++

ifneq (,$(strip $(DEBUG)))
  CFLAGS += -O0 -g
  hide = @
  strip-cmd =
else
  CFLAGS += -O2
  hide =
  strip-cmd = $(STRIP) $1
endif

SOURCES := ndk-depends.cc

OBJECTS=

define build-c-object
OBJECTS += $1
$1: $2
	mkdir -p $$(dir $1)
	$$(CC) $$(CFLAGS) $$(EXTRA_CFLAGS) -c -o $1 $2
endef

define build-cxx-object
OBJECTS += $1
$1: $2
	mkdir -p $$(dir $1)
	$$(CXX) $$(CFLAGS) $$(EXTRA_CFLAGS) -c -o $1 $2
endef

$(foreach src,$(filter %.c,$(SOURCES)),\
    $(eval $(call build-c-object,$(BUILD_DIR)/$(src:%.c=%.o),$(src)))\
)

$(foreach src,$(filter %.cc,$(SOURCES)),\
    $(eval $(call build-cxx-object,$(BUILD_DIR)/$(src:%.cc=%.o),$(src)))\
)

clean:
	rm -f $(EXECUTABLE)

$(EXECUTABLE): $(OBJECTS)
	$(CXX) $(LDFLAGS) $(OBJECTS) -o $@ $(EXTRA_LDFLAGS)
	$(call strip-cmd,$@)

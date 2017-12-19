LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE           := test-libjpeg-turbo-static
LOCAL_SRC_FILES        := test.c
LOCAL_STATIC_LIBRARIES := libjpeg_static
include $(BUILD_EXECUTABLE)

include $(CLEAR_VARS)
LOCAL_MODULE           := test-libjpeg-turbo-shared
LOCAL_SRC_FILES        := test.c
LOCAL_STATIC_LIBRARIES := libjpeg_shared
include $(BUILD_EXECUTABLE)

$(call import-module,libjpeg_turbo/1.4.2)

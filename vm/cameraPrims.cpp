/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2023 John Maloney, Bernat Romagosa, and Jens Mönig

// cameraPrims.cpp - ESP32 Camera primitives for select ESP32 boards with cameras.
// Requires 4MB of PSRam. Currently supports only the Freenova ESP32-WROVER board.

#include <Arduino.h>
#include <stdio.h>
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

#if defined(HAS_CAMERA)

#include "esp_camera.h"
#include "soc/rtc_cntl_reg.h"  // for brownout control

// The following pin definitions depend on the specific camera board.
// To support additional cameras, use #ifdefs to define the pins for each camera.

// CAMERA_MODEL_WROVER_KIT
#define PWDN_GPIO_NUM    -1
#define RESET_GPIO_NUM   -1
#define XCLK_GPIO_NUM    21
#define SIOD_GPIO_NUM    26
#define SIOC_GPIO_NUM    27

#define Y9_GPIO_NUM      35
#define Y8_GPIO_NUM      34
#define Y7_GPIO_NUM      39
#define Y6_GPIO_NUM      36
#define Y5_GPIO_NUM      19
#define Y4_GPIO_NUM      18
#define Y3_GPIO_NUM       5
#define Y2_GPIO_NUM       4
#define VSYNC_GPIO_NUM   25
#define HREF_GPIO_NUM    23
#define PCLK_GPIO_NUM    22

static int cameraIsInitialized;

static camera_config_t config;
static camera_fb_t *fb = NULL;

static framesize_t frameSize = FRAMESIZE_VGA;
static pixformat_t pixelFormat = PIXFORMAT_JPEG;
static int jpegQuality = 10;

static void updateConfiguration() {
	if (fb) {
		esp_camera_fb_return(fb);
		fb = NULL;
	}
 	if (cameraIsInitialized) {
		esp_camera_deinit(); // stop camera
		gpio_uninstall_isr_service();

		config.frame_size = frameSize; // FRAMESIZE_ + QVGA|CIF|VGA|SVGA|XGA|SXGA|UXGA
		config.pixel_format = pixelFormat; // PIXFORMAT_ + YUV422,GRAYSCALE,RGB565,JPEG
		config.jpeg_quality = jpegQuality; // 10-63, lower numbers are higher quality

		esp_err_t err = esp_camera_init(&config); // restart camera with new config
	}
}

static void initCamera() {
	if (cameraIsInitialized) return;

	WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0); // disable brownout detector

	config.ledc_channel = LEDC_CHANNEL_0;
	config.ledc_timer = LEDC_TIMER_0;
	config.pin_d0 = Y2_GPIO_NUM;
	config.pin_d1 = Y3_GPIO_NUM;
	config.pin_d2 = Y4_GPIO_NUM;
	config.pin_d3 = Y5_GPIO_NUM;
	config.pin_d4 = Y6_GPIO_NUM;
	config.pin_d5 = Y7_GPIO_NUM;
	config.pin_d6 = Y8_GPIO_NUM;
	config.pin_d7 = Y9_GPIO_NUM;
	config.pin_xclk = XCLK_GPIO_NUM;
	config.pin_pclk = PCLK_GPIO_NUM;
	config.pin_vsync = VSYNC_GPIO_NUM;
	config.pin_href = HREF_GPIO_NUM;
	config.pin_sccb_sda = SIOD_GPIO_NUM;
	config.pin_sccb_scl = SIOC_GPIO_NUM;
	config.pin_pwdn = PWDN_GPIO_NUM;
	config.pin_reset = RESET_GPIO_NUM;
	config.xclk_freq_hz = 10000000; // 8000000; // xxx was 20000000;

	// Does locating the framebuffer in PSRAM increase sync errors?
	config.fb_location = CAMERA_FB_IN_PSRAM;

	// buffer only one image
	config.fb_count = 1;
	config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;

	// set initial frame size and format
	config.frame_size = frameSize;
	config.pixel_format = pixelFormat;
	config.jpeg_quality = jpegQuality;

	// Initialize the Camera
	esp_err_t err = esp_camera_init(&config);
	if (err != ESP_OK) {
		reportNum("esp_camera_init() error", err);
		return;
	}

	sensor_t *s = esp_camera_sensor_get();
	s->set_vflip(s, 0);        // 1-Upside down, 0-No operation
	s->set_hmirror(s, 0);      // 1-Reverse left and right, 0-No operation
	s->set_brightness(s, 1);   // increase brightness
	s->set_saturation(s, -1);  // decrease saturation

	cameraIsInitialized = true;
}

OBJ primHasCamera(int argCount, OBJ *args) { return trueObj; }

OBJ primTakePhoto(int argCount, OBJ *args) {
	if (!cameraIsInitialized) initCamera();

	// take photo (return the framebuffer right before fb_get() to grab the current image)
	if (fb) esp_camera_fb_return(fb);
	fb = esp_camera_fb_get();

	if (!fb) {
		outputString("Photo capture failed");
		return falseObj;
	}

	// copy data into a new byte array
	int wordCount = (fb->len + 3) / 4;
	OBJ result = newObj(ByteArrayType, wordCount, falseObj);
	if (!result) return fail(insufficientMemoryError);
	memcpy((uint8 *) &FIELD(result, 0), fb->buf, fb->len);
	setByteCountAdjust(result, fb->len);

	return result;
}

OBJ primSetSize(int argCount, OBJ *args) {
	if (argCount < 1) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);
	char *arg = obj2str(args[0]);

	frameSize = FRAMESIZE_QVGA; // default
	if (strcmp(arg, "320x240") == 0) frameSize = FRAMESIZE_QVGA;
	if (strcmp(arg, "352x288") == 0) frameSize = FRAMESIZE_CIF;
	if (strcmp(arg, "640x480") == 0) frameSize = FRAMESIZE_VGA;
	if (strcmp(arg, "800x600") == 0) frameSize = FRAMESIZE_SVGA;
	if (strcmp(arg, "1024x768") == 0) frameSize = FRAMESIZE_XGA;
	if (strcmp(arg, "1280x1024") == 0) frameSize = FRAMESIZE_SXGA;
	if (strcmp(arg, "1600x1200") == 0) frameSize = FRAMESIZE_UXGA;

	updateConfiguration();
	return falseObj;
}

OBJ primSetEncoding(int argCount, OBJ *args) {
	if (argCount < 2) return fail(notEnoughArguments);
	if (!IS_TYPE(args[0], StringType)) return fail(needsStringError);

	char *encoding = obj2str(args[0]);
	pixelFormat = PIXFORMAT_JPEG; // default
	if (strcmp(encoding, "jpeg") == 0) pixelFormat = PIXFORMAT_JPEG;
	if (strcmp(encoding, "rgb565") == 0) pixelFormat = PIXFORMAT_RGB565;
	if (strcmp(encoding, "grayscale") == 0) pixelFormat = PIXFORMAT_GRAYSCALE;

	int quality = 100; // default
	if ((argCount > 1) && isInt(args[1])) quality = evalInt(args[1]); // 0-100
	if (quality < 0) quality = 0;
	if (quality > 100) quality = 100;
	jpegQuality = 60 - (quality / 2); // lower jpegQuality numbers give higher quality

	updateConfiguration();
	return falseObj;
}

#else

// stubs
OBJ primHasCamera(int argCount, OBJ *args) { return falseObj; }
OBJ primTakePhoto(int argCount, OBJ *args) { return falseObj; }
OBJ primSetSize(int argCount, OBJ *args) { return falseObj; }
OBJ primSetEncoding(int argCount, OBJ *args) { return falseObj; }

#endif

// Primitives

static PrimEntry entries[] = {
	{"hasCamera", primHasCamera},
	{"takePhoto", primTakePhoto},
	{"setSize", primSetSize},
	{"setEncoding", primSetEncoding},
};

void addCameraPrims() {
	addPrimitiveSet(CameraPrims, "camera", sizeof(entries) / sizeof(PrimEntry), entries);
}

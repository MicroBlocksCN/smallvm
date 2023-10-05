/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Copyright 2023 John Maloney, Bernat Romagosa, and Jens Mönig

// cameraPrims.cpp - ESP32 Camera Primitives for boards that support cameras
//
// Based partly on code by Rui Santos from:
// https://RandomNerdTutorials.com/esp32-cam-ov2640-camera-settings/

#include <Arduino.h>
#include <stdio.h>
#include <stdlib.h>

#include "mem.h"
#include "interp.h"

#if defined(HAS_CAMERA)

#include "esp_camera.h"
#include "soc/rtc_cntl_reg.h"  // for brownout control

/* Frame sizes:
  QVGA  320x240
  CIF   352x288
  VGA   640x480
  SVGA  800x600
  XGA   1024x768
  SXGA  1280x1024
  UXGA  1600x1200
*/

// Change pin definitions if you're using another ESP32 with camera module

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
static framesize_t frameSize = FRAMESIZE_UXGA;
static camera_fb_t *fb = NULL;

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
	config.xclk_freq_hz = 8000000; // 5000000; // xxx was 20000000;
	config.pixel_format = PIXFORMAT_JPEG; //YUV422,GRAYSCALE,RGB565,JPEG

	// keeping the framebuffer in PSRAM may increase sync errors
	config.fb_location = CAMERA_FB_IN_PSRAM;

	config.frame_size = frameSize; // FRAMESIZE_ + QVGA|CIF|VGA|SVGA|XGA|SXGA|UXGA
	config.jpeg_quality = 10; //10-63 lower number means higher quality

	// buffer just one image
	config.fb_count = 1;
	config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;

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

// xxx
outputString("PSRAM:");
reportNum("  psram size", ESP.getPsramSize());
reportNum("  psram free", ESP.getFreePsram());

	cameraIsInitialized = true;
}

static void updateConfiguration() {
	if (fb) {
		esp_camera_fb_return(fb);
		fb = NULL;
	}
 	if (cameraIsInitialized) {
		esp_camera_deinit(); // stop camera
		gpio_uninstall_isr_service();
		config.frame_size = frameSize;
		esp_err_t err = esp_camera_init(&config); // restart camera with new config
	}
}

OBJ primTakePhoto(int argCount, OBJ *args) {
	if (!cameraIsInitialized) initCamera();

	// take photo (return the framebuffer right before fb_get() to grab the current image)
	if (fb) esp_camera_fb_return(fb);
	fb = esp_camera_fb_get();

	if (!fb) {
		outputString("Photo capture failed");
		return falseObj;
	}

// xxx
reportNum("Got image! data bytecount", fb->len);
reportNum("  width", fb->width);
reportNum("  height", fb->height);

	// copy data into a new byte array
	int wordCount = (fb->len + 3) / 4;
	OBJ result = newObj(ByteArrayType, wordCount, falseObj);
	if (!result) return fail(insufficientMemoryError);
	memcpy((uint8 *) &FIELD(result, 0), fb->buf, fb->len);
	setByteCountAdjust(result, fb->len);

	return result;
}

OBJ primSetRes1(int argCount, OBJ *args) {
	frameSize = FRAMESIZE_QVGA;
	updateConfiguration();
	return falseObj;
}

OBJ primSetRes2(int argCount, OBJ *args) {
	frameSize = FRAMESIZE_XGA;
	updateConfiguration();
	return falseObj;
}

#else

// stubs
OBJ primTakePhoto(int argCount, OBJ *args) { return falseObj; }
OBJ primSetRes1(int argCount, OBJ *args) { return falseObj; }
OBJ primSetRes2(int argCount, OBJ *args) { return falseObj; }

#endif

// Primitives

static PrimEntry entries[] = {
	{"takePhoto", primTakePhoto},
	{"setRes1", primSetRes1},
	{"setRes2", primSetRes2},
};

void addCameraPrims() {
	addPrimitiveSet("camera", sizeof(entries) / sizeof(PrimEntry), entries);
}

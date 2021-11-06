// jpegPrims.c
// John Maloney, December 2015

#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>

#include "jpeglib.h"

#include "mem.h"
#include "interp.h"
#include "oop.h"

//******** JPEG Error Handling ********

struct my_error_mgr {
	struct jpeg_error_mgr pub;
	jmp_buf setjmp_buffer;
};

static void my_error_exit(j_common_ptr cinfo) {
	(*cinfo->err->output_message)(cinfo); // display the error message

	struct my_error_mgr *myerr = (void *) cinfo->err;
	longjmp(myerr->setjmp_buffer, 1); // return control to the caller
}

//******** Helper Functions ********

static unsigned char * encodeJPEG(int *bitmapData, int width, int height, int quality, unsigned long *outBufSizePtr) {
	// Returns a pointer to the compressed data buffer (which must be freed by the caller)
	// and sets *outBufSizePtr to the compressed data size in bytes.
	// Returns NULL if not successful.
	struct my_error_mgr jerr;
	struct jpeg_compress_struct cinfo;
	unsigned char *outBuf = NULL;

	*outBufSizePtr = 0; // clear *outBufSizePtr

	JSAMPLE *lineBuffer = malloc(3 * width);
	if (!lineBuffer) {
		primFailed("Could not allocate line buffer for JPEG encoding");
		return NULL;
	}

	// set up the normal JPEG error routines, then override error_exit
	cinfo.err = jpeg_std_error(&jerr.pub);
	jerr.pub.error_exit = my_error_exit;
	if (setjmp(jerr.setjmp_buffer)) {
		// if we get here, the JPEG code raised an error
		jpeg_destroy_compress(&cinfo);
		free(lineBuffer);
		primFailed("Could not allocate line buffer for JPEG encoding");
		return NULL;
	}

	// create and initialize the compressor
	jpeg_create_compress(&cinfo);
	jpeg_mem_dest(&cinfo, &outBuf, (size_t *) outBufSizePtr);
	cinfo.image_width = width;
	cinfo.image_height = height;
	cinfo.input_components = 3;
	cinfo.in_color_space = JCS_RGB;
	jpeg_set_defaults(&cinfo);
	jpeg_set_quality(&cinfo, quality, TRUE);

	// do compression, looping over all scanlines
	jpeg_start_compress(&cinfo, TRUE);
	JSAMPROW lines[1] = { lineBuffer }; // array with a single scan line, lineBuffer
	while (cinfo.next_scanline < cinfo.image_height) {
		// copy one line from from RGBA bitmap into RGB lineBuffer
		int *src = bitmapData + (cinfo.next_scanline * width);
		JSAMPLE *dst = lineBuffer;
		for (int i = 0; i < width; i++) {
			int argb = *src++;
			*dst++ = (argb >> 16) & 255;
			*dst++ = (argb >> 8) & 255;
			*dst++ = argb & 255;
		}
		(void) jpeg_write_scanlines(&cinfo, lines, 1);
	}
	jpeg_finish_compress(&cinfo);

	// cleanup
	jpeg_destroy_compress(&cinfo);
	free(lineBuffer);

	return outBuf;
}

static inline int isBitmap(OBJ bitmap) {
	return
		(objWords(bitmap) >= 3) &&
		isInt(FIELD(bitmap, 0)) && isInt(FIELD(bitmap, 1)) &&
		IS_CLASS(FIELD(bitmap, 2), BinaryDataClass);
}

//******** Primitives ********

static OBJ primJPEGEncode(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ bitmap = args[0];
	int quality = intArg(1, 100, nargs, args);
	if (!isBitmap(bitmap)) return primFailed("Bad bitmap");

	int w = obj2int(FIELD(bitmap, 0));
	int h = obj2int(FIELD(bitmap, 1));
	OBJ data = FIELD(bitmap, 2);
	if (objWords(data) != (w * h)) return primFailed("Bad bitmap");

	unsigned long byteCount = 0;
	unsigned char *compressed = encodeJPEG((int *) &FIELD(data, 0), w, h, quality, &byteCount);
	if (!compressed) return nilObj;

	// create a binary object to hold the compressed data
	unsigned int wordCount = ((byteCount + 3) / 4);
	if (!canAllocate(wordCount)) {
		free(compressed);
		return outOfMemoryFailure();
	}
	OBJ result = newBinaryObj(BinaryDataClass, wordCount);
	int extraBytes = 4 - (byteCount % 4);
	*(O2A(result)) |= extraBytes << EXTRA_BYTES_SHIFT;

	// copy the compressed data in to the binary object
	unsigned char *dst = (void *) &FIELD(result, 0);
	unsigned char *src = compressed;
	unsigned char *end = compressed + byteCount;
	while (src < end) *dst++ = *src++;

	free(compressed);
	return result;
}

static OBJ primJPEGDecode(int nargs, OBJ args[]) {
	if (nargs < 1) return notEnoughArgsFailure();
	OBJ data = args[0];
	if (!IS_CLASS(data, BinaryDataClass)) {
		return primFailed("Argument must be a BinaryData object");
	}
	long byteCount = objBytes(data);

	struct my_error_mgr jerr;
	struct jpeg_decompress_struct cinfo;

	// set up the normal JPEG error routines, then override error_exit
	cinfo.err = jpeg_std_error(&jerr.pub);
	jerr.pub.error_exit = my_error_exit;
	if (setjmp(jerr.setjmp_buffer)) {
		// if we get here, the JPEG code raised an error
		jpeg_destroy_decompress(&cinfo);
		return 0;
	}

	// create the decompressor, read the JPEG header, and start the decompressor
	jpeg_create_decompress(&cinfo);
	jpeg_mem_src(&cinfo, (unsigned char *) &FIELD(data, 0), byteCount);
	(void) jpeg_read_header(&cinfo, TRUE);

	int w = cinfo.image_width;
	int h = cinfo.image_height;
	OBJ bitmapData = newBinaryObj(BinaryDataClass, (w * h));
	OBJ bitmap = newInstance(newString("Bitmap"), 0);
	FIELD(bitmap, 0) = int2obj(w);
	FIELD(bitmap, 1) = int2obj(h);
	FIELD(bitmap, 2) = bitmapData;

	(void) jpeg_start_decompress(&cinfo);

	// create a one-scanline buffer (freed when the decompressor is destroyed)
	int stride = cinfo.output_width * cinfo.output_components;
	if (cinfo.output_width != w) {
		jpeg_destroy_decompress(&cinfo);
		return primFailed("Unexpected output width in jpegDecode");
	}
	JSAMPARRAY buffer = (*cinfo.mem->alloc_sarray) ((j_common_ptr) &cinfo, JPOOL_IMAGE, stride, 1);

	// decompress one scanline at a time
	int *base = (int *) &FIELD(bitmapData, 0);
	int *limit =  base + (w * h);
	while (cinfo.output_scanline < cinfo.output_height) {
		(void) jpeg_read_scanlines(&cinfo, buffer, 1);
		unsigned char *src = buffer[0];
		int *dst = (base + (w * (cinfo.output_scanline - 1)));
		int *end = dst + w;
		if (end > limit) end = limit;
		while (dst < end) {
			int r = *src++;
			int g = *src++;
			int b = *src++;
			*dst++ = (255 << 24) | (r << 16) | (g << 8) | b;
		}
	}
	(void) jpeg_finish_decompress(&cinfo);
	jpeg_destroy_decompress(&cinfo);

	return bitmap;
}

PrimEntry jpegPrimList[] = {
	{"-----", NULL, "JPEG"},
	{"jpegEncode",		primJPEGEncode,		"Encode a bitmap as JPEG and return the binary data. Optional quality setting is 0 to 100. Arguments: bitmap [quality]"},
	{"jpegDecode",		primJPEGDecode,		"Decode JPEG data and return a bitmap. Arguments: jpegData"},
};

PrimEntry* jpegPrimitives(int *primCount) {
	*primCount = sizeof(jpegPrimList) / sizeof(PrimEntry);
	return jpegPrimList;
}

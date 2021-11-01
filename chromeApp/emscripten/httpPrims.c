//
// networkPrims.c
// Primitives for network communication.
// Created by Daniel Owsiański on 26/08/2021.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h> /* assert() */

#ifdef EMSCRIPTEN
#include <emscripten.h>
#include <emscripten/fetch.h>

#else
#include <curl/curl.h>
#endif

#include "mem.h"
#include "interp.h"

#define MAX_PARALLEL 10   // number of simultaneous transfers
#define MAX_REQUESTS 100  // pool of simultaneous requests
#define DEFAULT_REQUEST_TIMEOUT 10000
#define DEFAULT_USER_AGENT "gp-blocks"

typedef enum { IN_PROGRESS,
               DONE,
               FAILED,
               CANCELLED } FetchStatus;

typedef struct {
    int id;
    FetchStatus status;
    int byteCount;
    char *data;
    void *headers;
} FetchRequest;

FetchRequest requests[MAX_REQUESTS];

static int nextFetchID = 100;

static void freeRequestHeaders(void *headers);

static int indexOfRequestWithID(int requestID) {
    int i;
    for (i = 0; i < MAX_REQUESTS; i++) {
        if (requests[i].id == requestID) break;
    }
    return (i >= MAX_REQUESTS) ? -1 : i;
}

static void cleanupRequestAtIndex(int index) {
    if (index < 0 || index > MAX_REQUESTS) return;

    // mark request as free and free the request data, if any
    requests[index].id = 0;
    if (requests[index].data) {
        free(requests[index].data);
    }

    freeRequestHeaders(requests[index].headers);

    requests[index].headers = NULL;
    requests[index].data = NULL;
    requests[index].byteCount = 0;
}

#ifdef EMSCRIPTEN

static void fetchDoneCallback(emscripten_fetch_t *fetch) {
    FetchRequest *request = fetch->userData;
    printf("🛬 Request finished. URL: >%s< ID: [%d] \n", fetch->url, request->id);

    request->data = malloc(fetch->numBytes);
    if (request->data) memmove(request->data, fetch->data, fetch->numBytes);
    request->byteCount = fetch->numBytes;
    request->status = DONE;

    emscripten_fetch_close(fetch);
}

static void fetchErrorCallback(emscripten_fetch_t *fetch) {
    FetchRequest *req = fetch->userData;
    printf("Fetch error, id = %d URL: >%s< status: %d\n", req->id, fetch->url, fetch->status);

    req->status = FAILED;

    emscripten_fetch_close(fetch);
}

static OBJ startRequest(int requestIndex, const char *url, const char *method, OBJ headersArray, const char *postBodyString, long timeout) {
    if (requestIndex >= MAX_REQUESTS) return nilObj;

    FetchRequest *request = &requests[requestIndex];

    emscripten_fetch_attr_t attr;
    emscripten_fetch_attr_init(&attr);

    strcpy(attr.requestMethod, method);
    attr.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY;
    attr.timeoutMSecs = timeout;

    if (headersArray != nilObj) {
        int count = WORDS(headersArray);

        // Two slots per header (name, value) plus end marker
        int headersSize = ((count * 2) + 1) * sizeof(const char *);
        const char **headers = (const char **)malloc(headersSize);

        if (headers) {
            memset(headers, 0, headersSize);

            int headersIndx = 0;
            for (int i = 0; i < count; i++) {
                OBJ obj = FIELD(headersArray, i);
                char *headerNameValue = obj2str(obj);

                //Find first ':' character and split string into two separate strings name and value
                char *colon = strchr(headerNameValue, ':');
                if (colon) {
                    long nameLen = (colon - headerNameValue);
                    char *name = malloc(nameLen + 1);
                    if (!name) {
                        freeRequestHeaders(headers);
                        headers = NULL;
                        break;
                    }
                    memcpy(name, headerNameValue, nameLen);
                    name[nameLen] = 0L;
                    headers[headersIndx++] = name;

                    long valueLen = strlen(headerNameValue) - nameLen;
                    char *value = malloc(valueLen);
                    if (!value) {
                        freeRequestHeaders(headers);
                        headers = NULL;
                        break;
                    }
                    // move one char afer the colon, so valueLen now covers also the zero marker at the end of headerNameValue
                    memcpy(value, (colon + 1), valueLen);
                    headers[headersIndx++] = value;
                }
            }
            attr.requestHeaders = headers;
            request->headers = headers;
        }
    }

    if (postBodyString) {
        attr.requestData = postBodyString;
        attr.requestDataSize = strlen(postBodyString);
    }

    attr.onsuccess = fetchDoneCallback;
    attr.onerror = fetchErrorCallback;

    attr.userData = request;

    emscripten_fetch(&attr, url);

    printf("🛫 Request ready to start for URL: >%s< ID: [%d] (at: [%d])\n", url, request->id, requestIndex);

    return int2obj(request->id);
}

static void freeRequestHeaders(void *headers) {
    if (!headers) {
        return;
    }

    const char **headerList = headers;
    int index = 0;
    while (true) {
        const char *headerItem = headerList[index++];
        if (headerItem) {
            free((void *)headerItem);
        } else {
            break;
        }
    }
    free(headers);
}

static void processRequestQueue() {
}

#else

static CURLM *curlMultiHandle = NULL;

size_t fetchWriteDataCallback(void *buffer, size_t size, size_t nmemb, void *userData) {
    size_t realSize = size * nmemb;
    FetchRequest *request = (FetchRequest *)userData;

    char *ptr = realloc(request->data, request->byteCount + realSize + 1);
    if (!ptr) {
        /* out of memory! */
        printf("not enough memory (realloc returned NULL)\n");
        return 0;
    }

    request->data = ptr;
    memcpy(&(request->data[request->byteCount]), buffer, realSize);
    request->byteCount += realSize;
    request->data[request->byteCount] = 0;

    return realSize;
}

static OBJ startRequest(int requestIndex, const char *url, const char *method, OBJ headersArray, const char *postBodyString, long timeout) {
    if (requestIndex >= MAX_REQUESTS) return nilObj;

    FetchRequest *request = &requests[requestIndex];

    if (curlMultiHandle == NULL) {
        curl_global_init(CURL_GLOBAL_ALL);
        curlMultiHandle = curl_multi_init();

        if (!curlMultiHandle) {
            return primFailed("Could not initate network connection");
        }

        // Limit the amount of simultaneous connections curl should allow:
        curl_multi_setopt(curlMultiHandle, CURLMOPT_MAXCONNECTS, (long)MAX_PARALLEL);
    }

    CURL *curl = curl_easy_init();
    if (!curl) {
        return primFailed("Could not initate network connection");
    }

    //https://curl.se/libcurl/c/curl_easy_setopt.html
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method);
    //curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, DEFAULT_USER_AGENT);  //can overwritten by headers
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, timeout);

    if (headersArray != nilObj) {
        struct curl_slist *headers = NULL;
        int count = WORDS(headersArray);
        for (int i = 0; i < count; i++) {
            OBJ obj = FIELD(headersArray, i);
            headers = curl_slist_append(headers, obj2str(obj));
        }
        curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
        request->headers = headers;
    }

    if (postBodyString) {
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, postBodyString);
    }

    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, fetchWriteDataCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)request);
    curl_easy_setopt(curl, CURLOPT_PRIVATE, request->id);
    curl_multi_add_handle(curlMultiHandle, curl);

    printf("🛫 Request ready to start for URL: >%s< ID: [%d] (at: [%d])\n", url, request->id, requestIndex);

    return int2obj(request->id);
}

static void freeRequestHeaders(void *headers) {
    if (!headers) {
        return;
    }
    curl_slist_free_all(headers);
}

static void processRequestQueue() {
    int stillAlive = 1;
    int messagesLeft = -1;
    CURLMsg *msg = NULL;

    if (!curlMultiHandle) {
        return;
    }

    curl_multi_perform(curlMultiHandle, &stillAlive);
    while ((msg = curl_multi_info_read(curlMultiHandle, &messagesLeft))) {
        if (msg->msg == CURLMSG_DONE) {
            int requestID;

            CURLcode msgCode = msg->data.result;
            CURL *curl = msg->easy_handle;
            curl_easy_getinfo(curl, CURLINFO_PRIVATE, &requestID);

            int requestIndex = indexOfRequestWithID(requestID);
            if (requestIndex > -1) {
                assert(CANCELLED == requests[requestIndex].status || IN_PROGRESS == requests[requestIndex].status);

                if (CANCELLED == requests[requestIndex].status) {
                    cleanupRequestAtIndex(requestIndex);
                } else if (msgCode == CURLE_OK) {
                    requests[requestIndex].status = DONE;
                    //https://stackoverflow.com/a/291006/12675559
                    // TODO: request.responseStatus = curl_easy_strerror(msgCode)
                } else {
                    printf("error on requestID: %d %s\n", requestID, curl_easy_strerror(msgCode));
                    requests[requestIndex].status = FAILED;
                    // TODO: request.errorMessage = curl_easy_strerror(msgCode)
                }
            }

            curl_multi_remove_handle(curlMultiHandle, curl);
            curl_easy_cleanup(curl);
        }
    }
}

#endif

// Returns request id on success, nil when there is no free slots for a new request (unlikely)
static OBJ primStartRequest(int nargs, OBJ args[]) {
    if (nargs < 5) return notEnoughArgsFailure();
    OBJ url = args[0];
    if (NOT_CLASS(url, StringClass)) return primFailed("URL argument must be a string");

    OBJ method = args[1];
    if (NOT_CLASS(method, StringClass)) return primFailed("HTTP method argument must be a string");

    OBJ headersArray = args[2];
    if (headersArray != nilObj && NOT_CLASS(headersArray, ArrayClass)) return primFailed("Headers argument must be an array");

    OBJ bodyObj = args[3];
    char *bodyString = NULL;
    if (bodyObj != nilObj) {
        if (NOT_CLASS(bodyObj, StringClass)) return primFailed("Body argument must be string");
        bodyString = obj2str(bodyObj);
    }

    OBJ timeoutObj = args[4];
    long timeoutVal = DEFAULT_REQUEST_TIMEOUT;
    if (timeoutObj != nilObj) {
        if (!isInt(timeoutObj)) return primFailed("Timeout argument must be an integer");
        timeoutVal = obj2int(timeoutObj);
    }

    // find an unused request
    int i;
    for (i = 0; i < MAX_REQUESTS; i++) {
        if (!requests[i].id) {
            requests[i].id = nextFetchID++;
            requests[i].status = IN_PROGRESS;
            requests[i].data = NULL;
            requests[i].byteCount = 0;

            break;
        }
    }
    if (i >= MAX_REQUESTS) return nilObj;  // no free request slots (unlikely)

    return startRequest(i, obj2str(url), obj2str(method), headersArray, bodyString, timeoutVal);
}

// Returns a BinaryData object on success, false on failure, and nil when fetch is still in progress.
static OBJ primFetchRequestResult(int nargs, OBJ args[]) {
    // First use this opportunity to process requests from the queue (for libcurl)
    processRequestQueue();

    if (nargs < 1) return notEnoughArgsFailure();
    if (!isInt(args[0])) return primFailed("Expected integer");
    int id = obj2int(args[0]);

    // find the fetch request with the given id
    int i = indexOfRequestWithID(id);
    if (i < 0) return falseObj;  // could not find request with id; report as failure

    OBJ result = nilObj;
    if (IN_PROGRESS == requests[i].status) {
        return result;
    }

    result = falseObj;

    if (DONE == requests[i].status && requests[i].data) {
        // allocate result object
        int byteCount = requests[i].byteCount;
        result = newBinaryData(byteCount);
        if (result) {
            memmove(&FIELD(result, 0), requests[i].data, byteCount);
        } else {
            printf("Insufficient memory for requested file (%ul bytes needed); skipping.\n", byteCount);
        }
    }

    cleanupRequestAtIndex(i);
    return result;
}

static OBJ primCancelRequest(int nargs, OBJ args[]) {
    if (nargs < 1) return notEnoughArgsFailure();
    if (!isInt(args[0])) return primFailed("Expected integer");
    int id = obj2int(args[0]);

    // find the fetch request with the given id
    int i = indexOfRequestWithID(id);
    if (i < 0) return nilObj;

    printf("🔴 primCancelRequest with ID: %d (%d)\n", id, i);
    if (IN_PROGRESS == requests[i].status) {
        requests[i].status = CANCELLED;
    } else {
        printf("?? can't cancel a request that is not in progress (%d), requestID: %d (%d)\n", requests[i].status, id, i);
    }

    processRequestQueue();
    return nilObj;
}

static PrimEntry httpPrimList[] = {
    {"-----", NULL, "Network: HTTP/HTTPS"},
    {"startRequest", primStartRequest, "Start downloading the contents of a URL. Return an id that can be used to get the result. Arguments: urlString, methodString, headersArrayOrNil, postBodyStringOrNil, timeoutIntegerOrNil"},
    {"fetchRequestResult", primFetchRequestResult, "Return the result of the fetch operation with the given id: a BinaryData object (success), false (failure), or nil if in progress. Argument: id"},
    {"cancelRequest", primCancelRequest, "Cancel the request (if exists) with the given id. Argument: id"},
};

PrimEntry *httpPrimitives(int *primCount) {
    *primCount = sizeof(httpPrimList) / sizeof(PrimEntry);
    return httpPrimList;
}

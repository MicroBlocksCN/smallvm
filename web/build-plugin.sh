if ! test -e crx.pem; then
    echo "Could not find a valid private key.\nPlease make sure crx.pem is in the working directory"
else
    if command -v chromium-browser; then
        chromium-browser --pack-extension=crx --pack-extension-key=crx.pem
    elif command -v google-chrome; then
        google-chrome --pack-extension=crx --pack-extension-key=crx.pem
    fi
    if test $? = 1; then
        echo "The extension could not be packaged.\nMake sure the Chromium browser or Google Chrome are installed in the system, and also that the extension private key can be found under environments/web/chromium/"
    else
        mv crx.crx uBlocks.crx
        echo "Extension packaged into uBlocks.crx"
    fi
fi

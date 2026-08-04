# PDFBox can optionally decode embedded JPEG-2000 images through Gemalto.
# HomeWallet only extracts selectable text, so that optional decoder is not
# included and R8 may safely ignore the reference.
-dontwarn com.gemalto.jp2.JP2Decoder

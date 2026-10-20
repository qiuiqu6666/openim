package chat.chat99.qr;

import android.content.Context;
import android.graphics.BitmapFactory;
import android.net.Uri;
import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;
import java.io.File;

/** On-device Latin OCR; called only on the plugin's bounded serial worker. */
final class ImageTextRecognizer {
    static String recognize(Context context, String path) throws Exception {
        File file = new File(path);
        if (!file.isFile() || file.length() > 32L * 1024 * 1024) {
            throw new IllegalArgumentException("Invalid image");
        }
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(path, bounds);
        int width = bounds.outWidth, height = bounds.outHeight;
        Runtime runtime = Runtime.getRuntime();
        long available = runtime.maxMemory() - (runtime.totalMemory() - runtime.freeMemory());
        if (width <= 0 || height <= 0 || width > 32768 || height > 32768
                || (long) width * height > 16L * 1024 * 1024
                || (long) width * height * 8 > available) {
            throw new IllegalArgumentException("Image too large");
        }
        TextRecognizer recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);
        try {
            InputImage image = InputImage.fromFilePath(context, Uri.fromFile(file));
            return Tasks.await(recognizer.process(image)).getText();
        } finally {
            recognizer.close();
        }
    }
}

package com.abdul.ascend.bridge;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.File;
import java.io.FileNotFoundException;
import java.util.List;

/** Lets the system camera write one capture into this app's private storage. Not exported; access is granted per photo. */
public final class PhotoProvider extends ContentProvider {
    static final String AUTHORITY = "com.abdul.ascend.bridge.photos";
    @Override public boolean onCreate() { return true; }
    File file(Uri uri) throws FileNotFoundException {
        List<String> parts = uri.getPathSegments();
        if (parts.size() != 2 || !"capture".equals(parts.get(0)) || !parts.get(1).matches("[a-f0-9-]{36}\\.jpg")) throw new FileNotFoundException();
        File folder = new File(getContext().getFilesDir(), "capture");
        folder.mkdirs();
        return new File(folder, parts.get(1));
    }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        return ParcelFileDescriptor.open(file(uri), ParcelFileDescriptor.parseMode(mode));
    }
    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        try {
            File f = file(uri);
            MatrixCursor cursor = new MatrixCursor(new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE});
            cursor.addRow(new Object[]{f.getName(), f.length()});
            return cursor;
        } catch (FileNotFoundException e) { return null; }
    }
    @Override public String getType(Uri uri) { return "image/jpeg"; }
    @Override public Uri insert(Uri uri, ContentValues values) { return null; }
    @Override public int delete(Uri uri, String selection, String[] args) { return 0; }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { return 0; }
}

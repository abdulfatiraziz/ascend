package com.abdul.ascend.bridge;

import android.app.Activity;
import android.os.Bundle;
import android.view.View;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.*;
import org.json.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Offline, read-only illustration library. No pairing, health permission or cloud account required. */
public final class ExerciseDemoActivity extends Activity {
    final ArrayList<String> ids=new ArrayList<>(),names=new ArrayList<>();
    WebView player;TextView title;Button play;boolean playing=false;int selected=0;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        playing=false;
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setPadding(24,24,24,24);root.setBackgroundColor(0xff0d0c12);
        title=new TextView(this);title.setText("Workout artwork");title.setTextSize(24);title.setTextColor(0xffeeeeef);root.addView(title);
        TextView note=new TextView(this);note.setText("Generated illustrations · transparent backgrounds");note.setTextColor(0xffaaa5b5);root.addView(note);
        Spinner picker=new Spinner(this);root.addView(picker);
        player=new WebView(this);player.setBackgroundColor(0xff0d0c12);
        player.getSettings().setJavaScriptEnabled(false);player.getSettings().setAllowFileAccess(false);player.getSettings().setAllowContentAccess(false);player.getSettings().setBlockNetworkLoads(true);player.getSettings().setBlockNetworkImage(true);
        player.setWebViewClient(new WebViewClient(){@Override public boolean shouldOverrideUrlLoading(WebView view,String url){return true;}});
        root.addView(player,new LinearLayout.LayoutParams(-1,0,1));
        play=new Button(this);play.setText("Subtle GIF motion: off");play.setOnClickListener(v->{playing=!playing;showDemo();});root.addView(play);
        TextView credits=new TextView(this);credits.setText("AI-generated artwork for Ascend. No personal photos used.\nDecorative GIF motion gently moves the illustration, not the exercise. Not a form demonstration. Motion is off by default.");credits.setTextColor(0xffaaa5b5);credits.setTextSize(11);root.addView(credits);
        Button back=new Button(this);back.setText("Back to Ascend");back.setOnClickListener(v->finish());root.addView(back);
        setContentView(root);
        try {
            JSONArray list=new JSONArray(read("catalog.json"));
            for(int i=0;i<list.length();i++){JSONObject e=list.getJSONObject(i);String id=e.getString("id");if(!id.matches("[a-z0-9-]{1,100}"))continue;ids.add(id);names.add(e.getString("name"));}
            ArrayAdapter<String> adapter=new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,names);picker.setAdapter(adapter);
            if(state!=null){selected=Math.min(Math.max(0,state.getInt("selected",0)),Math.max(0,ids.size()-1));playing=state.getBoolean("playing",false);}
            picker.setSelection(selected);picker.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener(){public void onNothingSelected(AdapterView<?> parent){}public void onItemSelected(AdapterView<?> parent,View view,int position,long id){selected=position;showDemo();}});
            showDemo();
        } catch(Exception ex){note.setText("Exercise illustrations unavailable. Your saved data is unchanged.");}
    }
    byte[] readBytes(String name)throws IOException {
        try(InputStream stream=getAssets().open(name);ByteArrayOutputStream out=new ByteArrayOutputStream()){stream.transferTo(out);return out.toByteArray();}
    }
    String read(String name)throws IOException {return new String(readBytes(name),StandardCharsets.UTF_8);}
    void showDemo(){
        if(selected<0 || selected>=ids.size())return;
        try {
            String type=playing?"gif":"png";
            String encoded=android.util.Base64.encodeToString(readBytes(ids.get(selected)+"."+type),android.util.Base64.NO_WRAP);
            String html="<!doctype html><meta name='viewport' content='width=device-width, initial-scale=1'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\"><style>html,body{margin:0;height:100%;background:#0d0c12;overflow:hidden}body{display:grid;place-items:center}img{width:100%;height:100%;object-fit:contain}</style><img alt='Generated workout illustration' src='data:image/"+type+";base64,"+encoded+"'>";
            player.loadDataWithBaseURL(null,html,"text/html","UTF-8",null);title.setText(names.get(selected));play.setText(playing?"Subtle GIF motion: on":"Subtle GIF motion: off");
        }catch(IOException ex){title.setText("Illustration unavailable");}
    }
    @Override protected void onSaveInstanceState(Bundle out){super.onSaveInstanceState(out);out.putInt("selected",selected);out.putBoolean("playing",playing);}
    @Override protected void onPause(){super.onPause();if(player!=null)player.onPause();}
    @Override protected void onResume(){super.onResume();if(player!=null)player.onResume();}
    @Override protected void onDestroy(){if(player!=null)player.destroy();super.onDestroy();}
}

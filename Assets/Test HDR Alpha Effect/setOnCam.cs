using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class setOnCam : MonoBehaviour
{
    public bool preserveFBAlpha = true;
    private Camera cam;
    private void OnEnable()
    {
        cam = GetComponent<Camera>();
        PlayerSettings.preserveFramebufferAlpha = preserveFBAlpha;
        Debug.Log($"preserveFramebufferAlpha = {Graphics.preserveFramebufferAlpha}");
        
    }

    private void OnGUI()
    {
        if(GUI.Button(new Rect(0,0,100,50),"capture screen"))
        {
            RenderTexture rt_srgb = RenderTexture.GetTemporary(Screen.width, Screen.height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.sRGB);
            rt_srgb.Create();
            CaptureScreen(cam, rt_srgb, "screen_srgb", Screen.width, Screen.height);

            RenderTexture rt_linear = RenderTexture.GetTemporary(Screen.width, Screen.height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Linear);
            rt_linear.Create();
            CaptureScreen(cam, rt_linear, "screen_linear", Screen.width, Screen.height);
        }
    }

    void CaptureScreen(Camera camera, RenderTexture rt, string name, int size, int height)
    {
        if (camera == null) return;

        camera.targetTexture = rt;
        camera.Render();

        RenderTexture bk = RenderTexture.active;
        RenderTexture.active = rt;
        Texture2D screen = new Texture2D(size, height, TextureFormat.ARGB32, false);
        Rect rect = new Rect(0, 0, size, height);
        screen.ReadPixels(rect, 0, 0);
        screen.Apply();

        camera.targetTexture = null;
        RenderTexture.active = bk;

        //GameObject.Destroy(rt);

        Color p = screen.GetPixel(size/2, height/2);
        Debug.Log($"center col = {p}");
        byte[] bytes = screen.EncodeToPNG();
        string full = Application.dataPath + "/" + name + ".png";
        Debug.Log(full);
        System.IO.File.WriteAllBytes(full, bytes);
    }

    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        
    }
}

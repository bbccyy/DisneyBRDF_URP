using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System.IO;
using UnityEngine.Experimental.Rendering;

public class ConvertCSVtoRT : ScriptableWizard
{
    [SerializeField]
    public RenderTexture rt;

    [SerializeField]
    public TextAsset csv;

    private string[] lines;
    private string[] elems;

    private int width = 0;
    private int height = 0;
    private Color[][] data;
    private Texture2D tex;

    [MenuItem("Tool/Convert Csv to RT")]
    static void DoConvertCSVtoRT()
    {
        ScriptableWizard.DisplayWizard<ConvertCSVtoRT>("ConvertCSV", "Convert");
    }

    private void OnWizardCreate()
    {
        Debug.Log("start");
        //readCSV();
        //SetupTex2D();
        //SaveToRT();

        ReadRTAndSaveToTexLocal();
        Debug.Log("done!");
    }

    private void OnWizardUpdate()
    {
        helpString = "plz set render center and render target!";
        isValid = rt != null;
    }


    void ReadRTAndSaveToTexLocal()
    {
        if (rt == null) return;
        
        Texture2D tmp = new Texture2D(rt.width, rt.height, GraphicsFormat.R16G16B16A16_SFloat, TextureCreationFlags.None);
        RenderTexture tmpRT = RenderTexture.active;
        RenderTexture.active = rt;
        tmp.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
        tmp.Apply();

        RenderTexture.active = tmpRT;

        var c = tmp.GetPixel(100, 100);
        Debug.Log(c.ToString());            //for test 

        var raw = tmp.EncodeToEXR();
        FileStream filestream = File.Open("Assets/Kena Rebuild UrbanGI/src/Gnorm.exr", FileMode.Create);
        BinaryWriter writer = new BinaryWriter(filestream);
        writer.Write(raw);
        filestream.Close();

        Texture.DestroyImmediate(tmp);
    }


    void SaveToRT()
    {
        if (rt == null) return;
        Graphics.Blit(tex, rt);
    }

    void SetupTex2D()
    {   
        tex = new Texture2D(width, height, GraphicsFormat.R16G16B16A16_SFloat, TextureCreationFlags.None);
        for (int i = 0; i < height; i++)
        {
            for (int j = 0; j < width; j++)
            {
                tex.SetPixel(j, i, data[i][j]);
            }
        }
        tex.Apply();
        var c = tex.GetPixel(100, 100);  //for test 
        Debug.Log(c.ToString());
    }

    void readCSV()
    {
        if (csv == null) return;

        lines = csv.text.Split('\n');
        elems = lines[0].Split(',');

        height = lines.Length - 1;
        width = (elems.Length - 1) / 4;

        Debug.Log(height + " " + width);

        data = new Color[height][];
        for (int i = 0; i < height; i++)
        {
            data[i] = new Color[width];
        }

        for (int i = 1; i < lines.Length; i++)
        {
            elems = lines[i].Split(',');
            for (int j = 1; j < elems.Length; j+=4)
            {
                var r = float.Parse(elems[j]);
                var g = float.Parse(elems[j+1]);
                var b = float.Parse(elems[j+2]);
                var a = float.Parse(elems[j+3]);
                Color c = new Color(r, g, b, a);
                data[height - i][j/4] = c;
            }
        }
    }

}

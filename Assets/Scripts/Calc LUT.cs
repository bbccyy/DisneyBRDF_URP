using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System.IO;

public class CalcLUT : EditorWindow
{
    private Material material = null;   //lut mat
    private RenderTexture lut = null;   //target lut
    [SerializeField]
    private string path = "Assets/BRDF Textures";
    private string subpath = null;

    [MenuItem("Tool/Create LUT")]
    public static void GeneratePrefilter()
    {
        GetWindow<CalcLUT>();
    }

    private void OnGUI()
    {
        lut = EditorGUILayout.ObjectField("Target RT", lut, typeof(RenderTexture), true, GUILayout.Width(300)) as RenderTexture;
        //cubemap = EditorGUILayout.ObjectField("Skybox", cubemap, typeof(Cubemap), true, GUILayout.Width(300)) as Cubemap;
        material = EditorGUILayout.ObjectField("Material", material, typeof(Material), true, GUILayout.Width(300)) as Material;
        //roughness = EditorGUILayout.Slider("Roughness", roughness, 0, 1);
        path = EditorGUILayout.TextField("Path", path, GUILayout.Width(1200));

        if (GUILayout.Button("Select Output"))
        {
            string inputpath = EditorUtility.OpenFolderPanel("select folder", path, "Assets");
            int index = inputpath.IndexOf("Assets");
            if (index >= 0)
            {
                subpath = path.Substring(index, path.Length - index);
                path = subpath;
            }
        }

        if (GUILayout.Button("Generate") && material != null && (subpath != null || path != null))
        {
            string realpath = path;
            if (string.IsNullOrEmpty(realpath)) realpath = subpath;
            
            if (lut == null)
            {
                lut = new RenderTexture(512, 512, 24);
                lut.enableRandomWrite = true;
                if (!lut.IsCreated())
                    lut.Create();
            }
            
            Graphics.Blit(lut, lut, material);
            CreateTexture(realpath, lut);
            /*
            if (!Directory.Exists(realpath))
            {
                Directory.CreateDirectory(realpath);
            }
            if (!AssetDatabase.Contains(lut))
            {
                AssetDatabase.CreateAsset(lut, realpath + "/LUT.png");
            }
            else
            {
                AssetDatabase.AddObjectToAsset(lut, realpath + "/LUT.png");
            }
            */
            AssetDatabase.ImportAsset(path);
            AssetDatabase.Refresh();

            //RenderTexture.active = tmp;
        }
    }

    void CreateTexture(string path, RenderTexture rt)
    {
        RenderTexture tmp = RenderTexture.active;
        RenderTexture.active = rt;
        Texture2D lut = new Texture2D(rt.width, rt.height, TextureFormat.ARGB32, false);
        lut.ReadPixels(new Rect(0, 0, rt.width, rt.height), 0, 0);
        byte[] bytes = lut.EncodeToPNG();
        FileStream filestream = File.Open(path + "/LUT.png", FileMode.Create);
        BinaryWriter writer = new BinaryWriter(filestream);
        writer.Write(bytes);
        filestream.Close();
        Texture.DestroyImmediate(lut);
        RenderTexture.active = tmp;
    }
}

using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

public class RenderCubeMap : ScriptableWizard
{
    public Transform renderCenter;  //must set any way
    public Cubemap cubemap;         //must set any way

    public Camera cam;          //set if you wanna build irradiance map
    public Material camMat;     //mat with irradiance shader + skybox texture

    [MenuItem("Tool/Create Cubemap[skybox|irradiance|prefilter]")]
    static void CreateCubemap()
    {
        ScriptableWizard.DisplayWizard<RenderCubeMap>("Create cubemap", "Create");
    }

    private void OnWizardCreate()
    {
        if (cam != null)
        {
            if (camMat != null)
            {
                Skybox skybox = cam.gameObject.GetComponent<Skybox>();
                if (!skybox)
                {
                    skybox = cam.gameObject.AddComponent<Skybox>();
                }
                skybox.material = camMat;
            }
            cam.RenderToCubemap(cubemap);
        }
        else
        {
            GameObject go = new GameObject();
            go.transform.position = renderCenter.position;
            go.transform.forward = renderCenter.forward;

            Camera cam = go.AddComponent<Camera>();
            cam.RenderToCubemap(cubemap);
            DestroyImmediate(cam);
        }
    }

    private void OnWizardUpdate()
    {
        helpString = "plz set render center and render target!";
        isValid = cubemap != null && 
            (
                (renderCenter != null)  || 
                (cam != null)
            );
    }
}

using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

public class ReplaceCameraRT : MonoBehaviour
{

    readonly int GlobalDepthTextureID = Shader.PropertyToID("_CameraDepthTex");
    readonly int GlobalColorTextureID = Shader.PropertyToID("_CameraColorTex");

    CommandBuffer cameraDepthCMD, cameraColorCMD;
    RenderTexture incameraDepthBuffer, incameraColorBuffer, depthTexture, colorTexture;
    
    private Camera cam;

    public void InitRT()
    {
        cam = GetComponent<Camera>();
        if (cam == null) return;

        incameraColorBuffer = RenderTexture.GetTemporary(cam.pixelWidth, cam.pixelHeight, 0, RenderTextureFormat.ARGB32);
        incameraColorBuffer.name = "main color buffer";
        incameraDepthBuffer = RenderTexture.GetTemporary(cam.pixelWidth, cam.pixelHeight, 24, RenderTextureFormat.Depth);
        incameraDepthBuffer.name = "main depth buffer";

        //RenderTargetBinding binding = new RenderTargetBinding(incameraColorBuffer, RenderBufferLoadAction.Load, RenderBufferStoreAction.Store, incameraDepthBuffer, RenderBufferLoadAction.Load, RenderBufferStoreAction.Store);

        //so called "off-screen rendering" 
        cam.SetTargetBuffers(incameraColorBuffer.colorBuffer, incameraDepthBuffer.depthBuffer);
        cam.targetTexture = incameraColorBuffer;

        cameraDepthCMD = new CommandBuffer() { name = "Depth Copy CMD" };
        cameraColorCMD = new CommandBuffer() { name = "Color Copy CMD" };
        cam.AddCommandBuffer(CameraEvent.AfterForwardOpaque, cameraDepthCMD);
        cam.AddCommandBuffer(CameraEvent.AfterForwardOpaque, cameraColorCMD);

        //deal depth
        cameraDepthCMD.Clear();
        RenderTexture.ReleaseTemporary(depthTexture);
        depthTexture = RenderTexture.GetTemporary(
            cam.pixelWidth, cam.pixelHeight, 0, RenderTextureFormat.RFloat);
        depthTexture.name = "Test Depth Holder";
        cameraDepthCMD.Blit(incameraDepthBuffer.depthBuffer, depthTexture);
        cameraDepthCMD.SetGlobalTexture(GlobalDepthTextureID, depthTexture);

        //deal color
        cameraColorCMD.Clear();
        RenderTexture.ReleaseTemporary(colorTexture);
        colorTexture = RenderTexture.GetTemporary(
            cam.pixelWidth, cam.pixelHeight, 0, RenderTextureFormat.ARGB32);
        colorTexture.name = "Test Color Holder";
        cameraColorCMD.Blit(incameraColorBuffer.colorBuffer, colorTexture);
        cameraColorCMD.SetGlobalTexture(GlobalColorTextureID, colorTexture);
    }

    // Start is called before the first frame update
    void Start()
    {
        InitRT();
    }

    private void Awake()
    {

    }

    // Update is called once per frame
    void Update()
    {
        //var tmp = cam.targetTexture;
    }

    public void DoDestroy()
    {
        RenderTexture.ReleaseTemporary(depthTexture);
        RenderTexture.ReleaseTemporary(colorTexture);
        RenderTexture.ReleaseTemporary(incameraColorBuffer);
        RenderTexture.ReleaseTemporary(incameraDepthBuffer);

        if (cam != null)
        {
            cam.RemoveAllCommandBuffers();
            cam.targetTexture = null;
        }
    }

    public void OnDestroy()
    {
        DoDestroy();
    }
}

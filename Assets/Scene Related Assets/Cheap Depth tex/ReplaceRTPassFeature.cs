using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class ReplaceRTPassFeature : ScriptableRendererFeature
{
    private RenderTexture colRT;
    private RenderTexture depRT;

    class ReplaceRTPass : ScriptableRenderPass
    {

        private RenderTexture colRT;
        private RenderTexture depRT;
        
        public void Setup(RenderTexture c, RenderTexture d)
        {
            colRT = c;
            depRT = d;
        }

        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in a performant manner.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var cam = renderingData.cameraData.camera;
            cam.SetTargetBuffers(colRT.colorBuffer, depRT.depthBuffer);
        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    ReplaceRTPass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new ReplaceRTPass();

        colRT = RenderTexture.GetTemporary(Camera.main.pixelWidth, Camera.main.pixelHeight, 0, RenderTextureFormat.RGB111110Float);
        colRT.name = "main color buffer";
        depRT = RenderTexture.GetTemporary(Camera.main.pixelWidth, Camera.main.pixelHeight, 24, RenderTextureFormat.Depth);
        depRT.name = "main depth buffer";

        m_ScriptablePass.Setup(colRT, depRT);   
        // Configures where the render pass should be injected.
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingOpaques - 1;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }

    protected override void Dispose(bool disposing)
    {
        RenderTexture.ReleaseTemporary(colRT);
        colRT = null;  
        RenderTexture.ReleaseTemporary(depRT);
        depRT = null;
    }
}



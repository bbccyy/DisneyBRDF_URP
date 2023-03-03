using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SimpleFullScreenBlit : ScriptableRendererFeature
{
    public Material kena_Prefix; public bool openPrefix;
    public Material kena_DirLight; public bool openDirLight;
    public Material kena_GI; public bool openGI;

    class FullScreenBlitPass : ScriptableRenderPass
    {
        private Material blitMat0 = null;
        private Material blitMat1 = null;
        private Material blitMat2 = null;
        private RenderTargetIdentifier source { get; set; }
        private RenderTargetHandle destination { get; set; }

        string m_ProfilerTag = "FullScreenBlit_GI";
        public FullScreenBlitPass(Material mat0, Material mat1, Material mat2, bool b0, bool b1, bool b2)
        {
            if (b0) blitMat0 = mat0;
            if (b1) blitMat1 = mat1;
            if (b2) blitMat2 = mat2;
        }

        public void Setup(RenderTargetIdentifier source, RenderTargetHandle destination)
        {
            this.source = source;
            this.destination = destination;
        }

        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in a performant manner.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);

            FrameCleanup(cmd);

            if (blitMat0)
                Blit(cmd, source, source, blitMat0);

            if (blitMat1)
                Blit(cmd, source, source, blitMat1);

            if (blitMat2)
                Blit(cmd, source, source, blitMat2);

            context.ExecuteCommandBuffer(cmd); 
            CommandBufferPool.Release(cmd);
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    FullScreenBlitPass m_ScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new FullScreenBlitPass(kena_Prefix, kena_DirLight, kena_GI, openPrefix, openDirLight, openGI);

        // Configures where the render pass should be injected.
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        m_ScriptablePass.Setup(renderer.cameraColorTarget, RenderTargetHandle.CameraTarget);
        renderer.EnqueuePass(m_ScriptablePass);
    }
}



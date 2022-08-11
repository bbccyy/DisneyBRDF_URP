using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


public enum GrabDepthStrategy
{
    None,
    GrabDepthFromRT,
    GrabColorFromRT,
}
public class GetRawDepthRenderPassFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class ViewSettings
    {
        public GrabDepthStrategy GrabDepthStrategy;
    }

    public ViewSettings settings = new ViewSettings();

    class PrintFBODepthRenderPass : ScriptableRenderPass
    {
        private string m_ProfilerTag;
        private RenderTargetHandle m_RenderTarget;
        private RenderTargetIdentifier m_depth_buffer;
        private RenderTargetIdentifier m_cam_depth_buffer;
        //private RenderTargetIdentifier source { get; set; }

        private GrabDepthStrategy setting;

        public PrintFBODepthRenderPass()
        {
            m_RenderTarget.Init("_CameraDepthTex");
            m_ProfilerTag = "Grab_active_render_buffer";
        }

        public void Setup(GrabDepthStrategy s)
        {
            this.setting = s;
        }

        // This method is called before executing the render pass.
        // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
        // When empty this render pass will render to the active camera render target.
        // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
        // The render pipeline will ensure target setup and clearing happens in a performant manner.
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
           

            m_cam_depth_buffer = renderingData.cameraData.renderer.cameraDepthTarget;
            m_depth_buffer = m_RenderTarget.Identifier();
            //ConfigureTarget(m_depth_buffer);
        }

        // Here you can implement the rendering logic.
        // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
        // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
        // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            //var cam = renderingData.cameraData.camera;
            //renderingData.cameraData.cameraTargetDescriptor.
            //cam.depthTextureMode = DepthTextureMode.None;
            //var curRT = cam.activeTexture; 
            //curRT = renderingData.cameraData.targetTexture;
            //var backbuffer = new RenderTargetIdentifier(BuiltinRenderTextureType.None);
            //var curRT = Graphics.activeDepthBuffer;
            RenderTargetIdentifier buffer;
            
            if (setting == GrabDepthStrategy.GrabDepthFromRT)
            {
                //buffer = m_cam_depth_buffer; 
                buffer = renderingData.cameraData.renderer.cameraDepthTarget;
            }
            else if (setting == GrabDepthStrategy.GrabColorFromRT)
            {
                buffer = renderingData.cameraData.renderer.cameraColorTarget;
            }
            else
            {
                //use fbo
                buffer = new RenderTargetIdentifier(BuiltinRenderTextureType.None);
            }

            CommandBuffer cmd = CommandBufferPool.Get(m_ProfilerTag);
            var descriptor = renderingData.cameraData.cameraTargetDescriptor;
            descriptor.colorFormat = RenderTextureFormat.ARGB32;
            descriptor.depthBufferBits = 24;
            cmd.GetTemporaryRT(m_RenderTarget.id, descriptor, FilterMode.Point);

            ConfigureTarget(m_RenderTarget.id);
            cmd.CopyTexture(buffer, m_RenderTarget.Identifier()); //Blit(cmd, buffer, m_RenderTarget.Identifier());
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
            

        }

        // Cleanup any allocated resources that were created during the execution of this render pass.
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(m_RenderTarget.id);
        }
    }

    PrintFBODepthRenderPass m_ScriptablePass;

    public class CreateTempDepthBufferPass : ScriptableRenderPass
    {
        private readonly int _depthRenderTargetId;
        private RenderTargetIdentifier _depthRenderTargetIdentifier;
        private RenderTargetIdentifier _cameraDepthAttachmentIdentifier;

        public CreateTempDepthBufferPass(int depthRenderTargetId) => _depthRenderTargetId = depthRenderTargetId;

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var depthTextureDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            depthTextureDescriptor.colorFormat = RenderTextureFormat.Depth;
            cmd.GetTemporaryRT(_depthRenderTargetId, depthTextureDescriptor, FilterMode.Point);

            _cameraDepthAttachmentIdentifier = renderingData.cameraData.renderer.cameraDepthTarget;
            _depthRenderTargetIdentifier = new RenderTargetIdentifier(_depthRenderTargetId);
            ConfigureTarget(_depthRenderTargetIdentifier);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            //if (!renderingData.SupportsTransparentWater()) return;

            var cmd = CommandBufferPool.Get();
            cmd.CopyTexture(_cameraDepthAttachmentIdentifier, _depthRenderTargetIdentifier);
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(_depthRenderTargetId);
        }
    }

    /// <inheritdoc/>
    public override void Create()
    {
        m_ScriptablePass = new PrintFBODepthRenderPass();

        // Configures where the render pass should be injected.
        m_ScriptablePass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques + 1;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        m_ScriptablePass.Setup(settings.GrabDepthStrategy);
        renderer.EnqueuePass(m_ScriptablePass);
    }
}



using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class TwoPassRenderPassFeature : ScriptableRendererFeature
{
    class TwoPassRenderPass : ScriptableRenderPass
    {
        string m_ProfilerTag;       //profiler采样器的名字 
        ProfilingSampler m_Sampler; //性能采样器本体 
        FilteringSettings m_FilterSettings; 
        RenderStateBlock m_RenderStateBlock; //Blend,Depth,Raster,Stencil中的0个或多个渲染状态 -> 被override 

        List<ShaderTagId> m_ShaderTags = new List<ShaderTagId> (); //该Pass需要用到的shader 



        public TwoPassRenderPass(string profilerTag, RenderPassEvent evt)
        {
           
            m_ShaderTags.Add(new ShaderTagId("BackFace")); //关联shader中的 Tags{"LightMode" = "BackFace"}
            //new ShaderTagId[] { new ShaderTagId("SRPDefaultUnlit"), new ShaderTagId("UniversalForward"), new ShaderTagId("UniversalForwardOnly") }

            base.renderPassEvent = evt;
            m_FilterSettings = new FilteringSettings(RenderQueueRange.all);
            m_RenderStateBlock = new RenderStateBlock(RenderStateMask.Nothing);

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
            //var cmd = CommandBufferPool.Get(m_ProfilerTag);
            //cmd.Clear();

            var sortFlags = SortingCriteria.RenderQueue;// renderingData.cameraData.defaultOpaqueSortFlags;
            var drawSettings = CreateDrawingSettings(m_ShaderTags, ref renderingData, sortFlags);
            //DrawRenderers用于绘制一批物体 
            //cullResults -> 记录物体，灯光，反射探针剔除的结果
            //DrawingSettings -> 设置绘制顺序时，使用哪个shader中的哪个pass 
            //filterSettings -> 设置过滤参数来渲染指定的Layer
            //RenderStateBlock -> 用来重载深度，模板写入方式 
            context.DrawRenderers(renderingData.cullResults, ref drawSettings, ref m_FilterSettings);
            //context.ExecuteCommandBuffer(cmd);
            //CommandBufferPool.Release(cmd);
        }

        // Cleanup any allocated resources that were created during the execution of this render pass.  
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    TwoPassRenderPass m_MyTwoPassScriptablePass;

    /// <inheritdoc/>
    public override void Create()
    {

        m_MyTwoPassScriptablePass = new TwoPassRenderPass( 
            "BackFaceLit", 
            RenderPassEvent.BeforeRenderingTransparents - 1
            );

        // Configures where the render pass should be injected.
        //m_MyTwoPassScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_MyTwoPassScriptablePass);
    }
}



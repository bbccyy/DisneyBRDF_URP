using UnityEngine;
using System.Collections.Generic;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


[System.Serializable]
public class GrabPassSetting
{
    private const string DefaultShaderLightMode = "UseColorTexture";
    private const string DefaultGrabbedTextureName = "_ScreenGrabTexture";

    public RenderPassEvent Event = RenderPassEvent.AfterRenderingOpaques;
    public string texName = DefaultGrabbedTextureName;
    public List<string> _shaderLightMode = new List<string> { DefaultShaderLightMode };
}

public class UseColorTexPass : ScriptableRenderPass
{
    static readonly string k_RenderTag = "UsePass";       //可在framedebug中看渲染
    private readonly SortingCriteria _sortingCriteria;

    private readonly List<ShaderTagId> _shaderTagIds;

    private FilteringSettings _filteringSettings;

    public UseColorTexPass(GrabPassSetting setting)
    {
        base.renderPassEvent = setting.Event + 1;   //right after grabpass 
        _filteringSettings = new FilteringSettings(RenderQueueRange.all);  
        _sortingCriteria = SortingCriteria.RenderQueue;
        _shaderTagIds = new List<ShaderTagId>();
        foreach(var mode in setting._shaderLightMode)
        {
            _shaderTagIds.Add(new ShaderTagId(mode));
        }
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get(k_RenderTag);
        cmd.Clear();

        var drawingSettings = CreateDrawingSettings(_shaderTagIds, ref renderingData, _sortingCriteria);
        context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref _filteringSettings);
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}

class GrabColTexPass : ScriptableRenderPass
{
    static readonly string k_RenderTag = "GrabPass";       //可在framedebug中看渲染
    RenderTargetIdentifier _cameraColorTarget;
    RenderTargetHandle _grabbedTextureHandle = RenderTargetHandle.CameraTarget;
    string m_GrabPassName = "_DefaultGrabPassTextureName";  //shader中的grabpass(纹理)名字
    public GrabColTexPass(GrabPassSetting setting)
    {
        renderPassEvent = setting.Event;
        m_GrabPassName = setting.texName;
        _grabbedTextureHandle.Init(m_GrabPassName);
    }

    public void SetUp(RenderTargetIdentifier currentTarget)
    {
        this._cameraColorTarget = currentTarget;
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        base.Configure(cmd, cameraTextureDescriptor);
        cmd.GetTemporaryRT(_grabbedTextureHandle.id, cameraTextureDescriptor);      //获取临时rt
        cmd.SetGlobalTexture(m_GrabPassName, _grabbedTextureHandle.Identifier());   //设置给shader中
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get(k_RenderTag);
        cmd.Clear();
        Blit(cmd, _cameraColorTarget, _grabbedTextureHandle.Identifier());
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(_grabbedTextureHandle.id);
    }
}

public class GrabPassFeature : ScriptableRendererFeature
{
    private GrabColTexPass m_GrabColorTexPass;
    private UseColorTexPass m_UseColorTexPass;
    public GrabPassSetting m_Setting;

    public override void Create()
    {
        m_GrabColorTexPass = new GrabColTexPass(m_Setting);
        m_UseColorTexPass = new UseColorTexPass(m_Setting);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        m_GrabColorTexPass.SetUp(renderer.cameraColorTarget);

        renderer.EnqueuePass(m_GrabColorTexPass);
        renderer.EnqueuePass(m_UseColorTexPass);
    }
}
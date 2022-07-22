using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AutoLoadPipelineAsset : MonoBehaviour
{
    public UniversalRenderPipelineAsset pipelineAsset;

    private void OnEnable()
    {
        if (pipelineAsset != null)
        {
            GraphicsSettings.renderPipelineAsset = pipelineAsset;
            //PlayerSettings.preserveFramebufferAlpha = false;
        }
    }
}

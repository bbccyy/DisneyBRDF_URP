using UnityEditor;
using UnityEngine;

public static class MyCustomEditor

{
    [MenuItem("Tool/PreserveFramebufferAlpha")]
    static void FramebufferAlpha()
    {

        PlayerSettings.preserveFramebufferAlpha = true;
        Debug.Log(PlayerSettings.preserveFramebufferAlpha);
    }
}
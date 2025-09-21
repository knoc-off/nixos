{ pkgs, lib, ... }: {
  programs.mpv = {
    enable = true;
    scripts = with pkgs.mpvScripts; [ sponsorblock thumbnail ];

    bindings = {
      "ALT+u" = "cycle-values profile fsr nis anime4k fsrcnnx";
      "ALT+r" = "apply-profile fsr ";
      "ALT+a" = "apply-profile anime4k ";
      "ALT+s" = "apply-profile fsrcnnx ";
      "ALT+f" = "apply-profile fix-bad-hd";
      #"ALT+0" = "apply-profile upscaling-needed";
    };

    defaultProfiles = [ "gpu-hq" ];

    config = {
      vo = "gpu-next";
      hwdec = "auto";
      "keep-open" = "yes";
      "ytdl-format" = "bestvideo[height<=?1080]+bestaudio/best";
      cache = "yes";
      "demuxer-max-bytes" = 16777216;
      osc = "no";
      
      # Audio configuration to prevent popping
      "audio-buffer" = 2.0;
      "audio-stream-silence" = "yes";
      "audio-wait-open" = 2.0;
      "gapless-audio" = "no";
      "audio-exclusive" = "no";
      ao = "pulse";
      "audio-samplerate" = 48000;
      "audio-channels" = "stereo";
      "volume-max" = 100;
    };

    profiles = let
      shadersPkg =
        "${pkgs.mpv-shim-default-shaders}/share/mpv-shim-default-shaders/shaders";
    in {
      fsr = {
        "profile-desc" = "AMD FSR 1.0 Upscaling";
        "glsl-shaders" = [ "${shadersPkg}/FSR.glsl" ];
        "glsl-shader-opts" = [ "fsr-strength=0" ];
      };

      nis = {
        "profile-desc" = "NVIDIA Image Scaling (all GPUs)";
        "glsl-shaders" = [ "${shadersPkg}/NVScaler.glsl:scale-sharpness=0.5" ];
      };

      anime4k = {
        "profile-desc" = "Anime4K Upscaling (Mode A)";
        "glsl-shaders" = [
          "${shadersPkg}/Anime4K_Denoise_Bilateral_Mode.glsl"
          "${shadersPkg}/Anime4K_Thin_HQ.glsl"
          "${shadersPkg}/Anime4K_Upscale_Denoise_CNN_x2_M.glsl"
        ];
      };

      fsrcnnx = {
        "profile-desc" = "FSRCNNX Neural Network Upscaling";
        "glsl-shaders" = [ "${shadersPkg}/FSRCNNX_x2_16-0-4-1.glsl" ];
      };

      "rescale-balanced" = {
        "profile-desc" =
          "Fix bad upscales with a balanced Anime4K chain. (Good start)";
        "glsl-shaders" = [
          # Downscale 1080p -> 540p to remove upscaling artifacts
          "${shadersPkg}/Anime4K_AutoDownscalePre_x2.glsl"
          # Upscale, denoise, and deblur in one step
          "${shadersPkg}/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl"
          # Optional line art sharpening
          "${shadersPkg}/Anime4K_Darken_HQ.glsl"
          "${shadersPkg}/Anime4K_Thin_HQ.glsl"
        ];
      };

      "rescale-hq" = {
        "profile-desc" =
          "Fix bad upscales with Restore + FSRCNNX. (Recommended Quality)";
        "glsl-shaders" = [
          # Downscale 1080p -> 540p to remove upscaling artifacts
          "${shadersPkg}/Anime4K_AutoDownscalePre_x2.glsl"
          # Powerful restoration shader for artifacts and noise
          "${shadersPkg}/Anime4K_Restore_CNN_VL.glsl"
          # High-quality neural network upscaler
          "${shadersPkg}/FSRCNNX_x2_16-0-4-1.glsl"
          # Final contrast-adaptive sharpening pass
          "${shadersPkg}/CAS-scaled.glsl"
        ];
      };

      "rescale-nnedi3" = {
        "profile-desc" =
          "Fix bad upscales with nnedi3. (Very High Quality, gpu-next only)";
        # This profile requires vo=gpu-next to be set in your main config
        vo = "gpu-next";
        "glsl-shaders" = [
          # Downscale 1080p -> 540p
          "${shadersPkg}/Anime4K_AutoDownscalePre_x2.glsl"
          # Restore artifacts before upscaling
          "${shadersPkg}/Anime4K_Restore_CNN_M.glsl"
        ];
        # "hook-shaders" = [
        #   # High-quality luma upscaler, great for lines
        #   "${shadersPkg}/nnedi3-nns64-win8x6.hook"
        # ];
      };

    };
  };
}

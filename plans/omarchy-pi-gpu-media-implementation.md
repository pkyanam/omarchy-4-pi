# Native Pi 4 GPU/media implementation handoff

November 8, 2026. Independent source lane; parent owns every physical Pi operation. Read root AGENTS, kickoff, corrected discovery, primary-source audit, progress, later release-ledger media entries and sibling runtime/stable AGENTS. Package/ISO roots have no AGENTS. No subagents, SSH, Pi access, benchmark, install, reboot, build, staging, commit, push, PR or external message was performed. The task's explicit no-external-messages instruction overrides the general Kai reporting rule for this lane.

## Decision

Retain the existing upstream VC4/V3D rendering stack. A Mesa replacement or VCHIQ-only configuration cannot provide the missing codec support. Pursue an upstream Linux media integration of the Pi H.264 codec and its required buffer-sharing/MMAL services, keeping the existing userspace V4L2 stateful API. That is the first practical end-to-end target because the matching packaged FFmpeg source already has the client. A separately maintained downstream kernel is a fallback candidate only after upstream delivery has been assessed; neither that assessment nor a working port has been completed here.

There is no justified installable kernel patch from this investigation. The bounded source audit identifies concrete blockers to a driver-only copy, including a newer downstream HEVC implementation under a different name. `build/upstream-pi/stable-4.5/gpu-media-candidate/h264-after-port.config.inactive` makes the future configuration requirements concrete, but is deliberately inactive and cannot create absent source. No shared recipe/config or main ledger was edited.

The provided board/package facts are 4GB BCM2711 Pi 4, Mesa/vulkan-broadcom 26.2.6 and Linux 7.3-32.1; they were not freshly measured by this lane. No claim about Pi OS parity, acceleration speed, power, Pi 5 or 8GB qualification follows.

## Rendering, decode, capture and compute

| Function | Actual implementation / prerequisite | Finding |
| --- | --- | --- |
| Display/scanout | Linux VC4 DRM; HDMI modes and compositor buffer import | Separate from codec. Preserve the current boot/display integration. |
| GLES rendering | Mesa V3D, Linux V3D DRM; kmsro bridges VC4 display and V3D rendering | Official Mesa documentation describes this arrangement. Existing desktop evidence belongs to the parent. |
| Vulkan graphics/compute | Mesa V3DV and supported kernel V3D submission capabilities | Compute support does not imply fixed-function media support. |
| Vulkan Video / VA-API decode | An implementation for the actual codec block and supported queues/profiles | Mesa 26.2.6 V3DV advertises no video extensions in its device-extension table. Installing vulkan-broadcom or setting `video-codecs=all` cannot add this implementation. No working Pi VA-API backend is demonstrated. |
| H.264 decode/encode | Downstream bcm2835-codec, MMAL over VCHIQ, firmware codec component and shared-buffer support | Missing coherent source set in target 7.3; config alone is insufficient. |
| HEVC decode | Downstream direct hardware stateless V4L2 Request driver; parser/request-aware userspace and Pi output format handling | Current pinned tree uses `hevc_dec`, `VIDEO_RPI_HEVC_DEC`, module `rpi-hevc-dec`; older `rpivid` advice is version-specific. Independent of H.264/MMAL. |
| CSI camera capture | Mainline bcm2835-unicam, sensor, graph, clocks/regulators and libcamera pipeline | Present source but disabled in saved config. Does not enable codec decode. Separate capture qualification required. |
| ISP / desktop recording | ISP processes raw image buffers; desktop capture uses compositor/portal and an encoder | ISP is not a decoder. Software screen capture can work without Pi hardware encoding; separate capture/cancel/playback validation remains necessary. |

Primary rendering reference: [Mesa V3D documentation](https://docs.mesa3d.org/drivers/v3d.html). Pinned Mesa files were initially fetched through a mirror, then independently fetched from official GitLab and matched byte-for-byte: [V3D screen](https://gitlab.freedesktop.org/mesa/mesa/-/blob/mesa-26.2.6/src/gallium/drivers/v3d/v3d_screen.c) SHA-256 `08ffadfaae980212d1a90cbe04813423783641ef35e243282620bb66e7fe880c`, [V3DV device](https://gitlab.freedesktop.org/mesa/mesa/-/blob/mesa-26.2.6/src/broadcom/vulkan/v3dv_device.c) `0fa4819abe4023376fe8c7eae4a9e20874751bd0f04071716d108bf8a2b1d706`. This establishes source behavior, not the installed binary's build provenance.

## Exact kernel ABI and H.264 port boundary

Rehashed `build/upstream-pi/linux-7.3.tar.xz`: `87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953`. The full member scan finds no bcm2835-codec, vc-sm-cma, rpivid or Raspberry Pi hevc_dec directory. An unrelated Hantro HEVC source is not a Pi decoder. Existing audit pins this archive to Linux `c03c1a14507dfaf8b856c2608f9ac216021fc222`; archive identity was verified here, Git identity remains inherited provenance.

The saved resolved 32.1 config enables `DRM_VC4=m`, `DRM_V3D=m`, `RASPBERRYPI_FIRMWARE=y`, `MEDIA_CONTROLLER=y`, `VIDEO_DEV=m`, `V4L2_MEM2MEM_DEV=m`, DMA shared buffers and CMA heaps. `BCM_VIDEOCORE=m` but `BCM2835_VCHIQ` is disabled; Unicam is disabled. A zero default CMA size is not proof the running firmware/DT reserves zero CMA. Do not prescribe a larger CMA reservation without parent memory-pressure and decoder-allocation evidence on this 4GB board.

Pinned downstream reference is Raspberry Pi Linux `2569533d6c33c15231fbc21704c87fcebc67173c` (the prior audit's rpi-6.12.y pin), not an asserted newest release. Exact source URLs and SHA-256 values are in `primary-source-manifest.json` under the candidate directory. [Codec source](https://github.com/raspberrypi/linux/blob/2569533d6c33c15231fbc21704c87fcebc67173c/drivers/staging/vc04_services/bcm2835-codec/bcm2835-v4l2-codec.c) hashes to `d0d4349dabc7d46656215f06ee1a0a8674404148cf7d7ee6e570999f82ea8944`.

A coherent port must resolve these actual boundaries:

1. Relocated includes: downstream codec reaches `interface/vchiq_arm/vchiq_bus.h` and `vchiq-mmal/*`; upstream 7.3 uses `drivers/platform/raspberrypi/vchiq-interface` and `vchiq-mmal`. Changing those paths only exposes deeper API differences.
2. Buffer ABI: downstream `struct mmal_buffer` adds `dma_buf`, `vcsm_handle`, `vc_handle`, `cmd`. All four are absent upstream. Downstream `vchiq_mmal_port` also adds `zero_copy` and serialized event context. Do not compile downstream consumers against upstream layouts or change layouts for only one module.
3. Shared-buffer lifecycle: downstream MMAL calls `vc_sm_cma_import_dmabuf`, `vc_sm_cma_int_handle`, `vc_sm_cma_free`; upstream lacks this service. Port its matching implementation, firmware messages, DMA address constraints, reference ownership and completion/error teardown together with MMAL. Replacing the calls with stubs or disabling zero-copy blindly is not a validated fallback.
4. Bus/device lifecycle: downstream VCHIQ registers `vcsm-cma`, `bcm2835-codec` and other children. Target registers only `bcm2835-audio`. An otherwise loadable codec module will not bind without the matching child registration, including failure cleanup/removal. Avoid copying unrelated camera/audio behavior wholesale.
5. Build integration: Kconfig/Makefile must link the port and require its services. Downstream codec selects `BCM2835_VCHIQ_MMAL`, `VIDEOBUF2_DMA_CONTIG`, `V4L2_MEM2MEM_DEV`; VCSM selects `BCM2835_VCHIQ`, `RBTREE`, `DMA_SHARED_BUFFER`. Check effective tristates after olddefconfig; symbols absent from the target tree are a hard failure. `/dev/vchiq` userspace access is not necessary for an in-kernel codec client.
6. Current 7.3 media/module interfaces: compile and modpost against the parent's exact fully patched/configured tree, including namespace syntax, vb2 callbacks, VCHIQ signatures and exported symbols. Successful regex/source checks below are not a substitute. Package kernel/headers/modules together; never copy Pi OS `.ko` files based on a similar kernel version or spoof vermagic.
7. Runtime firmware/DT: verify VCHIQ matching node, interrupt, shared-memory/DMA translation and usable VideoCore firmware under the actual PFTF Device Tree/UKI chain. Preserve the existing mainline-DMA overlay. Firmware must instantiate the codec components and successfully exchange buffers; module presence cannot establish this.

Smallest useful upstream-first sequence: buffer-sharing/MMAL prerequisite series with maintainers, codec child and H.264 stateful driver, then compliance and userspace functional qualification. Keep ISP/camera and HEVC separate. Obtain maintainer agreement on the supported service/buffer interface before making a private fork a shipping dependency. No maintainer contact was made. Upstream acceptance/timing is unresolved, not assumed impossible.

## HEVC is a different port and userspace ABI

The pinned Raspberry Pi directory is [drivers/media/platform/raspberrypi/hevc_dec](https://github.com/raspberrypi/linux/tree/2569533d6c33c15231fbc21704c87fcebc67173c/drivers/media/platform/raspberrypi/hevc_dec). Its Makefile builds `hevc_d.c`, `hevc_d_video.c`, `hevc_d_hw.c`, `hevc_d_h265.c`, with four local headers. All eight files were retrieved and hashed in `hevc-source-manifest.json`; it is no longer sufficient to look only for `rpivid` paths.

This implementation consumes standard stateless HEVC SPS/PPS/scaling/decode/slice controls and the V4L2 Request API. The symbolic controls exist in the target UAPI. It additionally consumes four Pi column-format constants **absent from target 7.3**: `V4L2_PIX_FMT_NV12MT_COL128`, `V4L2_PIX_FMT_NV12MT_10_COL128`, `V4L2_PIX_FMT_NV12_COL128`, `V4L2_PIX_FMT_NV12_10_COL128`. Importing numeric constants without their format/plane/stride/modifier semantics and client support is not a coherent ABI port. Request manual-completion support is already declared in the target; it is not a missing-prerequisite claim.

The driver requires named `hevc` and `intc` MMIO resources, IRQ, a clock returned by `devm_clk_get`, Raspberry Pi firmware max-rate query for `RPI_FIRMWARE_HEVC_CLK_ID`, and a 36-bit DMA mask. Downstream BCM2711 DTS supplies `brcm,bcm2711-hevc-dec` / `raspberrypi,hevc-dec`, MMIO `0x7eb00000` size `0x10000` plus `0x7eb10000` size `0x1000`, and GIC SPI98. Target BCM2711 DTS lacks that compatible. A DT binding/clock/firmware-provider audit and matching overlay/source integration remain open; do not add those addresses to the live board based only on this excerpt. Enabling VCHIQ cannot implement this direct hardware decoder.

[Linux stateless decoder contract](https://www.kernel.org/doc/html/latest/userspace-api/media/v4l/dev-stateless-decoder.html) requires userspace to maintain decode state and submit controls with each request. A stateful `hevc_v4l2m2m` client does not meet that contract. The packaged FFmpeg n9.0.2 configure/source excerpts provide V4L2 M2M but show no V4L2 Request backend in the inspected configure file. A Request-capable client plus these Pi output layouts must be selected, pinned and tested; no new FFmpeg fork was selected or built here. HEVC can be pursued independently but is not the shortest currently evidenced end-to-end path.

## Userspace/browser integration contract

Read package recipes at package-repo HEAD `474cdba825e630250f9b82b8b0055b5ecb594da3`. Runtime stable HEAD observed `0254fe47c17647ba84d16d3b571015451da794a4`; these are observations while sibling work continues, not installation claims.

The FFmpeg recipe is `2:9.0.2-2.1`, enables libv4l2, does not disable V4L2 M2M, and its pinned [n9.0.2 configure](https://github.com/FFmpeg/FFmpeg/blob/n9.0.2/configure) autodetects `linux/videodev2.h`, `sem_timedwait`, M2M capability and format constants. `h264_v4l2m2m` exists in [decoder source](https://github.com/FFmpeg/FFmpeg/blob/n9.0.2/libavcodec/v4l2_m2m_dec.c). Confirm it in the actual installed package before changing any recipe. No FFmpeg change is justified merely from missing `/dev/video*`.

Parent's first post-port decode-only exercise should use a known public/local H.264 fixture with SHA-256, bounded duration and explicit decoder selection, for example `ffmpeg -hide_banner -loglevel verbose -c:v h264_v4l2m2m -i fixture.mp4 -t 20 -an -f null -`. Capture the selected device/format, completion/errors, decoded frame count and matching software-decode frame checksums where formats allow. This command is a proposed state-changing hardware exercise, not a read-only probe and was not run here. Follow with real Wayland playback; decoding to null does not establish zero-copy display, colors, A/V sync or speed.

The Chromium recipe repackages upstream Omarchy Chromium `148.0.7778.96` build21, recipe release22. It provides no GN build arguments/source-build evidence. Matching [Chromium args.gni](https://github.com/chromium/chromium/blob/148.0.7778.96/media/gpu/args.gni) defaults `use_v4l2_codec=false`; VA-API defaults may be enabled for Linux arm64. That default does **not** prove the binary used it. Retrieve actual Omarchy browser build provenance before considering a rebuild. Build-time V4L2 support, decoder factory routing, sandbox device access, Ozone Wayland and dmabuf import must all work. Do not substitute runtime flags for omitted build support, disable the sandbox, or advertise unsupported VA-API/Vulkan decode.

After kernel/client decode passes, parent should inspect `chrome://gpu` and per-stream `chrome://media-internals` in the actual browser with a fixed H.264 sample; record codec, selected hardware decoder and fallback reason. Repeat on the application's normal Wayland session, including resolution changes, seek, EOS, tab close and repeated playback. VP9/AV1 playback or GPU compositing is not evidence of H.264 acceleration. Browser path, portal recording and HEVC remain separate acceptance gates.

## Verification, outputs and parent gates

`build/upstream-pi/stable-4.5/gpu-media-candidate/audit-abi.py` was run locally against the real pinned sources and exact archive. Full output is `abi-audit.json`, stderr `abi-audit.log`. It rehashes the archive, scans codec path absence, compares real buffer-field/service and UAPI identifiers, enumerates actual VCHIQ child registration and V3DV video extension declarations, and records source hashes. This is reproducible source compatibility evidence, not a compiler or ABI-layout proof. Source excerpts retain copyright/license notices. Failed guessed paths and GitHub API timeouts are retained and explicitly superseded by successful raw-source retrieval, never used as absence evidence.

| State | Result |
| --- | --- |
| Source-tested | Exact archive hash and source absence; downstream MMAL/VCSM/child-registration gaps; HEVC fourcc/DT gaps; official Mesa 26.2.6 byte comparison; FFmpeg/Chromium source prerequisites. |
| Candidate | Inactive H.264 configuration contract only; source audit and pinned evidence. No driver patch advertised as compatible. |
| Built | Nothing in this lane. Parent owns budget and compiler builds. |
| Installed / physically verified | Nothing in this lane. Existing rendering evidence remains parent-owned. |
| Unresolved | Full H.264 prerequisite port, media/VCHIQ compile/modpost and upstream review; coherent HEVC UAPI/client/DT/clock port; actual browser build provenance and all decode/capture runtime acceptance. |

Parent validation order: review source/maintainer boundary; implement prerequisites in owning package/kernel sources; apply inactive config only after sources exist and verify resolved symbols; compile with the coordinated budget and retain complete logs/modpost/artifact hashes; prepare rollback and matching kernel/headers/firmware/DT payload; parent alone performs controlled installation/reboot; discover devices by queried driver/capabilities rather than fixed video numbers; run V4L2 compliance and real bounded H.264 decode; then playback/browser/capture acceptance and repeated matched workload trials. Verify device permissions through normal session policy; do not grant blanket access to every video or firmware device. Keep software fallbacks visible while unresolved.

Do not spend a kernel build on the configuration contract alone: it still cannot supply the absent sources. This handoff closes a bounded source investigation and leaves the implementation/runtime gates explicitly open.

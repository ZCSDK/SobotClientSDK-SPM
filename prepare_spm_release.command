#!/usr/bin/env python3
"""双击或在终端运行：准备本地 SPM 发布包，不提交或上传 GitHub。"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
import zipfile

# 每次发版只需改这里，或运行时输入版本，或传入 --version 4.7.4。
DEFAULT_VERSION = "4.7.4"
# 脚本放在 SPM 仓库根目录；默认复用旁边 CocoaPods 发布仓库的同版产物。
REPO = Path(__file__).resolve().parent
DEFAULT_SOURCE = REPO.parent / "chat_client_sdk_ios"
# ZIP 名称必须与 Package.swift 的三个 binaryTarget 下载文件名保持一致。
MODULES = ("SobotCommon", "SobotChatClient", "SobotKit")
RESOURCE_PATH = Path("Sources/SobotClientSDKResources/Resources")
# 本地框架镜像保持与发布 ZIP 同源；此目录仍由 .gitignore 排除。
ARTIFACT_PATH = REPO / "Artifacts"
# 正式版使用三段版本号；允许 SemVer 预发布标识，禁止四段 Pod 版本号。
VERSION_PATTERN = r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"


def run(*args, cwd=REPO):
    """执行本地命令；任何失败都停止后续操作并保留工具错误输出。"""
    return subprocess.run(args, cwd=cwd, check=True, text=True, stdout=subprocess.PIPE).stdout.strip()


def require(condition, message):
    """将输入、结构和一致性检查失败转换为清晰的中文错误。"""
    # 条件不满足时不能继续制作发布包。
    if not condition:
        raise RuntimeError(message)


def update_manifest(original, version, checksums):
    """精确更新版本和按模块匹配的 checksum，保留其余清单配置和注释。"""
    updated, count = re.subn(r'(let\s+releaseVersion\s*=\s*")[^"]+(")',
                             lambda m: m[1] + version + m[2], original)
    require(count == 1, "Package.swift 必须且只能包含一个 releaseVersion 声明。")
    for module in MODULES:
        # 使用整个 binaryTarget 边界，避免把某个模块的 checksum 写到另一个模块。
        pattern = r'(\.binaryTarget\(\s*name:\s*"' + module + r'",\s*url:\s*"[^"\n]+",\s*checksum:\s*")[0-9a-fA-F]{64}("\s*\))'
        updated, count = re.subn(pattern, lambda m: m[1] + checksums[module] + m[2], updated)
        require(count == 1, f"无法唯一定位 {module} 的 binaryTarget，未修改原清单。")
    return updated


def main():
    """先准备和验证所有产物，再备份并同步本地框架、清单与资源。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="本轮 SPM 版本，例如 4.7.4；不传则交互输入")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE,
                        help="输入目录：三个 XCFramework、SobotKit.bundle、PrivacyInfo.xcprivacy")
    parser.add_argument("--output", type=Path, help="自定义输出目录，必须尚不存在")
    args = parser.parse_args()
    # 双击时提示版本；无交互的自动化调用必须明确传入版本号。
    if args.version is None:
        require(sys.stdin.isatty(), "非交互执行请传入 --version 4.7.4。")
        args.version = input(f"请输入 SPM 版本号，回车使用 {DEFAULT_VERSION}：").strip() or DEFAULT_VERSION
    version = args.version
    match = re.fullmatch(VERSION_PATTERN, version)
    require(match is not None, "版本格式应为 4.7.4 或 4.7.4-beta.1。")
    # SemVer 的纯数字预发布标识不允许前导零。
    if match[4]:
        require(all(not (part.isdigit() and len(part) > 1 and part.startswith("0"))
                    for part in match[4].split(".")), "预发布数字标识不能有前导零。")
    source = args.source.expanduser().resolve()
    output = (args.output or Path.home() / "Desktop" /
              f"SobotSPM_{version}_发布包_{datetime.now():%Y%m%d_%H%M%S}").expanduser().resolve()
    print(f"\n本轮版本：{version}\n输入产物：{source}\n发布目录：{output}", flush=True)
    require(not output.exists(), f"输出目录已存在，不能覆盖：{output}")
    # 发布输出不能放在将被整体替换的目录内，否则备份也会被一起替换。
    for destination in (ARTIFACT_PATH.resolve(), (REPO / RESOURCE_PATH).resolve()):
        require(output != destination and destination not in output.parents,
                f"输出目录不能放在同步目标目录内：{destination}")
    for tool in ("swift", "ditto", "git"):
        require(shutil.which(tool), f"缺少命令：{tool}，请先安装 Xcode 命令行工具。")
    require(not run("git", "tag", "--list", version), f"本地已有 Tag {version}，请检查是否已经发布。")
    # 输入来自 Pod 仓库时校验分发版本，避免误用旧版；预发布复用相同正式版本二进制。
    podspec = source / "SobotClientSDK.podspec"
    if podspec.exists():
        pod_version = re.search(r's\.version\s*=\s*[\'"]([^\'"]+)', podspec.read_text())
        require(pod_version and pod_version[1] == version.split("-")[0],
                "输入 podspec 版本与本轮 SPM 版本不一致，请先更新输入产物。")
    for module in MODULES:
        framework = source / f"{module}.xcframework"
        require((framework / "Info.plist").is_file(), f"缺少 {framework}/Info.plist")
        with (framework / "Info.plist").open("rb") as stream:
            libraries = plistlib.load(stream).get("AvailableLibraries", [])
        require(libraries, f"{module} 的 XCFramework 没有平台切片。")
        for library in libraries:
            require((framework / library["LibraryIdentifier"] / library["LibraryPath"]).exists(),
                    f"{module} 缺少声明的平台切片：{library['LibraryIdentifier']}")
    require((source / "SobotKit.bundle").is_dir(), "输入目录缺少同版 SobotKit.bundle。")
    require((source / "PrivacyInfo.xcprivacy").is_file(), "输入目录缺少 PrivacyInfo.xcprivacy。")
    with (source / "PrivacyInfo.xcprivacy").open("rb") as stream:
        plistlib.load(stream)
    manifest = REPO / "Package.swift"
    original = manifest.read_text()
    # 压缩前预检清单布局；实际 checksum 在压缩后填入。
    update_manifest(original, version, {name: "0" * 64 for name in MODULES})
    output.mkdir(parents=True, exist_ok=False)
    checksums = {}
    # 临时目录只用于本次准备，退出时自动清理；发布目录保留结果或失败现场。
    with tempfile.TemporaryDirectory(prefix="sobot-spm-") as temporary:
        staging = Path(temporary)
        # 先制作输入快照；ZIP 与最终 Artifacts 都使用此快照，避免分别读取不同文件。
        staged_artifacts = staging / "Artifacts"
        staged_artifacts.mkdir()
        for module in MODULES:
            shutil.copytree(source / f"{module}.xcframework",
                            staged_artifacts / f"{module}.xcframework", symlinks=True)
        (staged_artifacts / "LOCAL_BASELINE.txt").write_text(
            f"SPM release target: {version}\nInput directory: {source}\n"
            "Local preparation only; release and runtime validation are not implied.\n")
        shutil.copytree(REPO / "Sources", staging / "Sources", symlinks=True)
        staged_resources = staging / RESOURCE_PATH
        shutil.rmtree(staged_resources)
        staged_resources.mkdir()
        shutil.copytree(source / "SobotKit.bundle", staged_resources / "SobotKit.bundle", symlinks=True)
        shutil.copy2(source / "PrivacyInfo.xcprivacy", staged_resources / "PrivacyInfo.xcprivacy")
        for module in MODULES:
            print(f"正在压缩并校验 {module}…", flush=True)
            archive = output / f"{module}.xcframework.zip"
            run("ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr",
                str(staged_artifacts / f"{module}.xcframework"), str(archive))
            with zipfile.ZipFile(archive) as zipped:
                require(zipped.testzip() is None, f"ZIP 完整性检查失败：{archive.name}")
                require(f"{module}.xcframework/Info.plist" in zipped.namelist(), "ZIP 根目录结构不正确。")
                require(all(name.startswith(f"{module}.xcframework/") for name in zipped.namelist()),
                        f"{archive.name} 存在额外顶层内容。")
            checksums[module] = run("swift", "package", "compute-checksum", str(archive))
            require(re.fullmatch(r"[0-9a-f]{64}", checksums[module]), "Swift checksum 输出无效。")
            require(hashlib.sha256(archive.read_bytes()).hexdigest() == checksums[module], "SHA-256 交叉校验失败。")
        updated = update_manifest(original, version, checksums)
        (staging / "Package.swift").write_text(updated)
        print("正在解析新 Package.swift…", flush=True)
        parsed = run("swift", "package", "--package-path", str(staging), "dump-package", cwd=staging)
        targets = {target["name"]: target for target in json.loads(parsed)["targets"]}
        for module in MODULES:
            expected_url = f"https://github.com/ZCSDK/SobotClientSDK-SPM/releases/download/{version}/{module}.xcframework.zip"
            require(targets[module]["url"] == expected_url and targets[module]["checksum"] == checksums[module],
                    f"{module} 的解析下载地址或 checksum 不匹配。")
        (output / "package-manifest.json").write_text(parsed + "\n")
        (output / "checksums.txt").write_text("".join(f"{checksums[name]}  {name}.xcframework.zip\n" for name in MODULES))
        (output / "Package.swift").write_text(updated)
        backup = output / "原文件备份"
        backup.mkdir()
        shutil.copy2(manifest, backup / "Package.swift")
        shutil.copytree(REPO / RESOURCE_PATH, backup / "Resources", symlinks=True)
        # 保留整个旧 Artifacts（包括旧基线说明），更新失败时恢复原状。
        had_artifacts = ARTIFACT_PATH.exists()
        if had_artifacts:
            shutil.copytree(ARTIFACT_PATH, backup / "Artifacts", symlinks=True)
        # 检测打包期间的并发修改，避免覆盖用户刚刚编辑的清单。
        require(manifest.read_text() == original, "打包期间 Package.swift 已被修改，请重新运行。")
        try:
            # 整体替换框架目录，删除旧版已不存在的切片和文件。
            if had_artifacts:
                shutil.rmtree(ARTIFACT_PATH)
            shutil.copytree(staged_artifacts, ARTIFACT_PATH, symlinks=True)
            # 整体替换资源目录，避免保留上一版已经删除的文件。
            shutil.rmtree(REPO / RESOURCE_PATH)
            shutil.copytree(staged_resources, REPO / RESOURCE_PATH, symlinks=True)
            replacement = REPO / ".Package.swift.release-tmp"
            require(not replacement.exists(), f"临时文件已存在：{replacement}")
            replacement.write_text(updated)
            os.replace(replacement, manifest)
        except BaseException:
            # 更新失败时还原原清单、框架和资源；备份始终保留在发布目录。
            shutil.copy2(backup / "Package.swift", manifest)
            if (REPO / RESOURCE_PATH).exists():
                shutil.rmtree(REPO / RESOURCE_PATH)
            shutil.copytree(backup / "Resources", REPO / RESOURCE_PATH, symlinks=True)
            # 新目录可能只复制了一部分，恢复前先清理本轮写入的内容。
            if ARTIFACT_PATH.exists():
                shutil.rmtree(ARTIFACT_PATH)
            # 原先没有 Artifacts 时，失败后仍保持不存在。
            if had_artifacts:
                shutil.copytree(backup / "Artifacts", ARTIFACT_PATH, symlinks=True)
            raise
    # 输出实际输入和待办，不能把本地打包成功当成远程发布/真机验收成功。
    instructions = (f"本地准备完成：SPM {version}\n输入目录：{source}\n"
                    f"Package.swift 已更新，配套资源已同步。原文件保存在 原文件备份/。\n"
                    "仅将本目录三个 .xcframework.zip 原文件上传 GitHub Release，不要重新压缩。\n"
                    f"上传前检查远端是否已有 {version}，核对 README 和资源，提交清单及资源并推送同名 Tag。\n"
                    "Release 使用相同 Tag，上传三个 ZIP 并公开发布，随后进行远程安装和真机验证。\n"
                    "本脚本未查询远端版本、未提交、未创建 Tag、未上传；未重新编译 SDK。\n"
                    "本地 Artifacts 已同步为本轮 ZIP 的输入快照，仍被 .gitignore 排除，不提交 Git。\n")
    (output / "发布说明.txt").write_text(instructions)
    print(f"\n{instructions}\n发布文件夹：{output}", flush=True)


if __name__ == "__main__":
    # 双击执行结束后保留终端窗口，方便阅读成功路径或失败原因。
    interactive = sys.stdin.isatty() and len(sys.argv) == 1
    status = 0
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print(f"\n准备失败：{error}\n请处理错误后重试；不要上传不完整的输出目录。", file=sys.stderr)
        status = 1
    if interactive:
        input("按回车退出…")
    sys.exit(status)

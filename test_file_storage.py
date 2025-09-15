#!/usr/bin/env python3
"""
文件存储功能测试脚本

测试TaskFileManager类的各项功能：
- 创建任务目录
- 保存和读取文本文件
- 保存和读取音频文件
- 保存和读取字幕文件
- 获取文件路径和信息
- 删除任务文件
"""

import os
import sys
import tempfile
import shutil
from pathlib import Path

# 添加项目根目录到Python路径
sys.path.append(str(Path(__file__).parent))

from server.utils.file_manager import TaskFileManager

def test_file_manager():
    """测试文件管理器功能"""
    print("开始测试文件存储功能...")
    
    # 创建临时测试目录
    test_base_dir = tempfile.mkdtemp(prefix="tts_test_")
    print(f"测试目录: {test_base_dir}")
    
    try:
        # 初始化文件管理器
        file_manager = TaskFileManager(storage_root=test_base_dir)
        
        # 测试数据
        task_id = "test_task_123"
        test_text = "这是一个测试文本，用于验证文件存储功能。Hello, this is a test text for file storage validation."
        test_audio_data = b"fake_audio_data_for_testing" * 100  # 模拟音频数据
        test_srt_content = """1
00:00:00,000 --> 00:00:03,000
这是一个测试字幕

2
00:00:03,000 --> 00:00:06,000
This is a test subtitle
"""
        
        print("\n1. 测试创建任务目录...")
        task_dir = file_manager.create_task_directory(task_id)
        print(f"   任务目录已创建: {task_dir}")
        assert os.path.exists(task_dir), "任务目录创建失败"
        
        print("\n2. 测试保存文本文件...")
        text_file_path = file_manager.save_text_file(task_id, test_text)
        print(f"   文本文件已保存: {text_file_path}")
        assert os.path.exists(text_file_path), "文本文件保存失败"
        
        print("\n3. 测试读取文本文件...")
        read_text = file_manager.read_text_file(task_id)
        print(f"   读取的文本长度: {len(read_text)}")
        assert read_text == test_text, "文本文件读取内容不匹配"
        
        print("\n4. 测试保存音频文件...")
        audio_file_path = file_manager.save_audio_file(task_id, test_audio_data)
        print(f"   音频文件已保存: {audio_file_path}")
        assert os.path.exists(audio_file_path), "音频文件保存失败"
        
        print("\n5. 测试读取音频文件...")
        read_audio = file_manager.read_audio_file(task_id)
        print(f"   读取的音频数据长度: {len(read_audio)}")
        assert read_audio == test_audio_data, "音频文件读取内容不匹配"
        
        print("\n6. 测试保存字幕文件...")
        srt_file_path = file_manager.save_srt_file(task_id, test_srt_content)
        print(f"   字幕文件已保存: {srt_file_path}")
        assert os.path.exists(srt_file_path), "字幕文件保存失败"
        
        print("\n7. 测试读取字幕文件...")
        read_srt = file_manager.read_srt_file(task_id)
        print(f"   读取的字幕内容长度: {len(read_srt)}")
        assert read_srt == test_srt_content, "字幕文件读取内容不匹配"
        
        print("\n8. 测试获取文件路径...")
        file_paths = file_manager.get_file_paths(task_id)
        print(f"   文件路径信息: {file_paths}")
        assert file_paths['text_file'], "文本文件路径获取失败"
        assert file_paths['audio_file'], "音频文件路径获取失败"
        assert file_paths['srt_file'], "字幕文件路径获取失败"
        
        print("\n9. 测试获取文件信息...")
        file_info = file_manager.get_file_info(task_id)
        print(f"   文件信息: {file_info}")
        assert file_info['text_size'] > 0, "文本文件大小获取失败"
        assert file_info['audio_size'] > 0, "音频文件大小获取失败"
        assert file_info['srt_size'] > 0, "字幕文件大小获取失败"
        
        print("\n10. 测试删除任务文件...")
        file_manager.delete_task_files(task_id)
        print(f"    任务文件已删除")
        assert not os.path.exists(task_dir), "任务目录删除失败"
        
        print("\n✅ 所有测试通过！文件存储功能正常工作。")
        
    except Exception as e:
        print(f"\n❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False
    
    finally:
        # 清理测试目录
        if os.path.exists(test_base_dir):
            shutil.rmtree(test_base_dir)
            print(f"\n测试目录已清理: {test_base_dir}")
    
    return True

def test_error_handling():
    """测试错误处理"""
    print("\n开始测试错误处理...")
    
    # 创建临时测试目录
    test_base_dir = tempfile.mkdtemp(prefix="tts_error_test_")
    
    try:
        file_manager = TaskFileManager(storage_root=test_base_dir)
        
        # 测试读取不存在的文件
        print("\n1. 测试读取不存在的文本文件...")
        try:
            file_manager.read_text_file("nonexistent_task")
            print("   ❌ 应该抛出FileNotFoundError")
            return False
        except FileNotFoundError:
            print("   ✅ 正确抛出FileNotFoundError")
        
        print("\n2. 测试读取不存在的音频文件...")
        try:
            file_manager.read_audio_file("nonexistent_task")
            print("   ❌ 应该抛出FileNotFoundError")
            return False
        except FileNotFoundError:
            print("   ✅ 正确抛出FileNotFoundError")
        
        print("\n3. 测试读取不存在的字幕文件...")
        try:
            file_manager.read_srt_file("nonexistent_task")
            print("   ❌ 应该抛出FileNotFoundError")
            return False
        except FileNotFoundError:
            print("   ✅ 正确抛出FileNotFoundError")
        
        print("\n✅ 错误处理测试通过！")
        
    except Exception as e:
        print(f"\n❌ 错误处理测试失败: {e}")
        return False
    
    finally:
        # 清理测试目录
        if os.path.exists(test_base_dir):
            shutil.rmtree(test_base_dir)
    
    return True

if __name__ == "__main__":
    print("=" * 60)
    print("TTS文件存储功能测试")
    print("=" * 60)
    
    # 运行基本功能测试
    basic_test_passed = test_file_manager()
    
    # 运行错误处理测试
    error_test_passed = test_error_handling()
    
    print("\n" + "=" * 60)
    print("测试结果汇总:")
    print(f"基本功能测试: {'✅ 通过' if basic_test_passed else '❌ 失败'}")
    print(f"错误处理测试: {'✅ 通过' if error_test_passed else '❌ 失败'}")
    
    if basic_test_passed and error_test_passed:
        print("\n🎉 所有测试通过！文件存储功能已准备就绪。")
        sys.exit(0)
    else:
        print("\n💥 部分测试失败，请检查实现。")
        sys.exit(1)
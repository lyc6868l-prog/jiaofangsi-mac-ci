"""
DJ Admin Service Client - 命名管道客户端

通过命名管道与管理员服务通信，执行需要提权的操作。
"""

import json
import time
from win32 import win32file
from win32 import win32pipe
import pywintypes

PIPE_NAME = r"\\.\pipe\DJAdminService"
BUFFER_SIZE = 4096
CONNECT_TIMEOUT = 5.0


class AdminServiceClient:
    """管理员服务客户端"""
    
    def __init__(self):
        self._pipe = None
    
    def connect(self) -> bool:
        """
        连接到管理员服务。
        返回是否成功连接。
        """
        try:
            # 尝试打开已存在的管道
            pipe = win32file.CreateFile(
                PIPE_NAME,
                win32file.GENERIC_READ | win32file.GENERIC_WRITE,
                0,
                None,
                win32file.OPEN_EXISTING,
                0,
                None,
            )
            
            # 设置管道模式
            win32pipe.SetNamedPipeHandleState(
                pipe,
                win32pipe.PIPE_READMODE_MESSAGE,
                None,
                None,
            )
            
            self._pipe = pipe
            return True
            
        except pywintypes.error as e:
            if e.winerror == 2:  # 文件未找到（服务未启动）
                return False
            raise AdminServiceError(f"连接失败: {e}")
    
    def disconnect(self):
        """断开连接"""
        if self._pipe:
            try:
                win32file.CloseHandle(self._pipe)
            except Exception:
                pass
            self._pipe = None
    
    def request(self, action: str, params: dict, timeout: float = 30.0) -> dict:
        """
        发送请求并等待响应。
        
        Args:
            action: 操作名称
            params: 操作参数
            timeout: 超时时间（秒）
        
        Returns:
            响应字典，包含 success 和 data/error
        """
        if not self._pipe:
            raise AdminServiceError("未连接到管理员服务")
        
        request_data = json.dumps(
            {"action": action, **params},
            ensure_ascii=False
        )
        
        try:
            win32file.WriteFile(self._pipe, request_data.encode("utf-8"))
            
            # 读取响应
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                try:
                    code, data = win32file.ReadFile(self._pipe, BUFFER_SIZE)
                    if code == 0:
                        response_text = data.decode("utf-8")
                        return json.loads(response_text)
                except pywintypes.error as e:
                    if e.winerror == 232:  # 管道关闭
                        break
                    time.sleep(0.1)
            
            raise AdminServiceError("等待响应超时")
            
        except pywintypes.error as e:
            raise AdminServiceError(f"通信错误: {e}")
        except json.JSONDecodeError as e:
            raise AdminServiceError(f"响应解析失败: {e}")
    
    def format_disk(
        self,
        disk_number: int,
        filesystem: str = "fat32",
        volume_label: str = "PIONEER",
        timeout: float = 120.0,
    ) -> dict:
        """
        格式化磁盘。
        
        Args:
            disk_number: 磁盘编号
            filesystem: 文件系统 (fat32/exfat)
            volume_label: 卷标
            timeout: 超时时间
        
        Returns:
            结果字典 {"success": bool, "error": str|None}
        """
        return self.request(
            "format_disk",
            {
                "disk_number": disk_number,
                "filesystem": filesystem,
                "volume_label": volume_label,
            },
            timeout=timeout,
        )
    
    def ping(self) -> bool:
        """测试服务是否可用"""
        try:
            response = self.request("ping", {}, timeout=5.0)
            return response.get("success", False)
        except AdminServiceError:
            return False


class AdminServiceError(Exception):
    """管理员服务错误"""
    pass


def format_disk_via_service(
    disk_number: int,
    filesystem: str = "fat32",
    volume_label: str = "PIONEER",
) -> dict:
    """
    通过管理员服务格式化磁盘。
    
    Returns:
        {"success": bool, "error": str|None}
    """
    client = AdminServiceClient()
    
    if not client.connect():
        return {
            "success": False,
            "error": "管理员服务未运行，请重启应用以启动服务",
        }
    
    try:
        return client.format_disk(disk_number, filesystem, volume_label)
    finally:
        client.disconnect()
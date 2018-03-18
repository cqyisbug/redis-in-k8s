# -*- coding:UTF-8 -*-

import os
import json


class ResultInfo(object):
    def __init__(self, code=0, message=""):
        self.all = {}
        self.all.setdefault("code", code)
        self.all.setdefault("message", message)

    def tostring(self):
        return json.dumps(self.all)


def build(tag):
    cmd = "docker build -t {0} ./images"
    result = os.system(cmd.format(tag))
    if result == 0:
        return ResultInfo(code=0, message="制作镜像成功,image:" + tag).tostring()
    else:
        return ResultInfo(code=6, message="制作镜像失败").tostring()

#!C:\Python27\python.exe
#
#

import sys
import subprocess
import win32com.client


class WinWord(object):
    def open(self, fname):
        self.app = subprocess.Popen("WINWORD", [fname])
    def exit(self):
        self.app.terminate()

class WinWordCOM(object):
    def __init__(self):
        self.app = win32com.client.Dispatch("Word.Application")
        self.app.Visible = 1
        self.app.DisplayAlerts = 0

    def open(self, fname, repair=True):
        self.app.Documents.OpenNoRepairDialog(fname, AddToRecentFiles=False,
                                              OpenAndRepair=repair)

    def close(self):
        self.app.ActiveDocument.close()

    def exit(self):
        self.app.Quit()


def main(args):
    if len(args) != 2:
        print "tracer fname"
        return 1

    word = WinWord()
    word.open(fname)
    time.sleep(30)

    if word.poll() == 0:
        return 0
    else:
        word.terminate()
        return 2

if __name__ == "__main__":
    sys.exit(main(sys.argv))

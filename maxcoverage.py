

class CodeCoverage(object):
    def __init__(self):
        self.bv = BitVector()

    def __cmp__(self, other):
        if len(self) == len(other):
            return 0
        if len(self) > len(other):
            return 1
        return -1

    def __len__(self):
        return self.bv.count_bits()
    def __and__(self, other):
        return self.bv & other.bv
    def __neg__(self):
        return ~self.bv


def max_coverage(cc_list):
    full_list = sorted(cc_list)

    optimal_templates = []
    while len(full_list) > 0:
        candidate = full_list.pop(0)

        optimal_templates.append(candidate)

        for t in full_list:
            covered = t & ~candidate
            if len(covered) == 0:
                full_list.remove(t)



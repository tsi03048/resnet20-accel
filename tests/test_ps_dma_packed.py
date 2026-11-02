import struct,unittest
import numpy as np
from tools.ps_dma_vectors import artifacts as old_artifacts
from tools.ps_dma_packed_vectors import artifacts as packed_artifacts

class PackedTransferTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.old,cls.old_meta=old_artifacts();cls.packed,cls.meta=packed_artifacts()
    def test_same_logical_scalars_as_v1(self):
        for name,raw in self.packed.items():
            _,kind,_=struct.unpack('<III',raw[:12])
            native=np.frombuffer(raw[12:],dtype='u1').astype('<u4').tobytes() if kind<2 else raw[12:]
            self.assertEqual(native,self.old[name][12:],name)
    def test_logical_count_and_protocol_version(self):
        for name,raw in self.packed.items():
            old_header=struct.unpack('<III',self.old[name][:12]);new_header=struct.unpack('<III',raw[:12])
            self.assertEqual(new_header[0],0x52323032);self.assertEqual(new_header[1:],old_header[1:])
            _,kind,count=new_header;self.assertEqual(len(raw)-12,count if kind<2 else count*4)
    def test_transfer_footprint_from_actual_packets(self):
        names=['input0.bin','weight.bin','bias.bin','multiplier.bin','shift.bin']
        old_bytes=sum(len(self.old[n]) for n in names);new_bytes=sum(len(self.packed[n]) for n in names)
        self.assertEqual(old_bytes,1094068);self.assertEqual(new_bytes,279844)
        self.assertEqual(old_bytes-new_bytes,814224);self.assertEqual(new_bytes//4,69961)

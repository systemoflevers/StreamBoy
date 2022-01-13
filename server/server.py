#!/usr/bin/python3
import socket
import socketserver
import threading
import itertools
import ffmpeg
import pyautogui

frame_rate = '20'

two_bit_lookup = [3-(i //64) for i in range(256)]
byte_lookup = [85 * i for i in two_bit_lookup]

two_bit_upper = [i >> 1 for i in two_bit_lookup]
two_bit_lower = [i & 1 for i in two_bit_lookup]


# row x column
tile_coordinates = list(itertools.product(range(18), range(20)))

def getTileBytes(r, c, frame):
    tile_values = []
    indexes = []
    start = 20*8*8*r + c*8
    for i in range(8):
        indexes.append(start)
        tile_values += frame[start:start+8]
        start += 20*8
    return bytes(tile_values)


def tileRowTo2bpp(row_bytes):
    "Turns an 8 byte row into 2 bytes in 2bpp format."
    upper = 0
    lower = 0
    upper_bits = []
    lower_bits = []
    for b in row_bytes:
        upper <<= 1
        u = two_bit_upper[b]
        upper_bits.append(u)
        upper |= u
        lower <<= 1
        l = two_bit_lower[b]
        lower_bits.append(l)
        lower |= l
    return bytes([upper, lower])

def makeTile(r, c, frame):
    tile_bytes = getTileBytes(r, c, frame)
    
    tile = bytes()
    for row in chunker(tile_bytes, 8):
        tile += tileRowTo2bpp(row)
    return tile

def frameToTiles(frame):
    tiles = bytes()
    for (r, c) in tile_coordinates:
        tiles += makeTile(r, c, frame)
    return tiles


def chunker(seq, size):
    return (seq[pos:pos + size] for pos in range(0, len(seq), size))

class ClientTracker:
    def __init__(self):
        self.lock = threading.Lock()
        self.data = []
        self.wfiles = []

    
    def add_client(self, data, wfile):
        with self.lock:
            new_id = len(self.data)
            self.data.append(data)

            for w in self.wfiles:
                w.write(f'{new_id}: {data}\n'.encode())
            self.wfiles.append(wfile)
        return new_id

    def update_client(self, id, data):
        with self.lock:
            self.data[id] = data
            for i, wfile in enumerate(self.wfiles):
                if i == id: continue
                wfile.write(f'{id}: {data}\n'.encode())


def frameGrabber():
    print("starting ffmpeg")
    process1 = (
        ffmpeg
        .input(":0.0+836,533", s="320x240", f="x11grab", r=frame_rate)
        .output('pipe:', s="160x144", format='rawvideo', pix_fmt='gray', vf="eq=brightness=0.5:contrast=2")
        .run_async(pipe_stdout=True, pipe_stderr=True)
    )
    print("I guess it should be started now?")
    print(process1)
    while True:

        #print("hi?")
        in_bytes = process1.stdout.read(160 * 144)
        if not in_bytes:
            break
        tile_data[0] = frameToTiles(in_bytes)

client_tracker = ClientTracker()

class InputWaiter:
    def __init__(self, got_input_event):
        self.got_input_event = got_input_event

tile_data = [None]
tile_data_iterator = [None]

class Button:
    def __init__(self, key_name):
        self.key_name = key_name
        self.state = False

    def update(self, new_state):
        if self.state == new_state:
            return
        self.state = new_state
        if new_state:
            #print(f'{self.key_name} down')
            pyautogui.keyDown(self.key_name)
        else:
            #print(f'{self.key_name} up')
            pyautogui.keyUp(self.key_name)

def DecodeButton(code, handlers):
    """decode |code| and use appropriate handlers

    Handlers should be a list of 8 entries, code should be 8 bits.
    """
    for h in reversed(handlers):
        h.update(code & 1)
        code >>= 1

class RelayTCPHandler(socketserver.StreamRequestHandler):
    """Relays messages to and from clients.
    Broadcasts any messages from the client being handled to all other
    connected clients.
    """
    def handle(self):
        data = 0
        #id = client_tracker.add_client(data, self.wfile)
        self.wfile.flush()

        handlers = [Button(key) for key in [
            'down',
            'up',
            'left',
            'right',
            'space',
            'enter',
            'alt',
            'ctrl'
        ]]
        while True:
            #print('got msg')
            msg = self.rfile.read(1)
            #msg = self.request.recv(16)
            
            #client_tracker.update_client(id, msg)

            #print("Data Recieved from client is: {}".format(msg))
            value = int.from_bytes(msg,'little', signed=False)
            print(f'got {value:08b} {value}')
            DecodeButton(value, handlers)

            tiles_to_send = tile_data[0] #next(tile_data_iterator[0])
            #print(f'data to send length: {len(tiles_to_send)}')

            self.wfile.write(tiles_to_send)


current_set = None
def main():
    print("starting")
    print(len(tile_coordinates))
    #frameGrabber()
    threading.Thread(target=frameGrabber, daemon=True).start()
    #with open('tile_data.bin', 'br') as f:
    #    tile_data1 = f.read()

    #with open('tile_data2.bin', 'br') as f:
    #    tile_data2 = f.read()

    #tile_data.append(tile_data1)
    #tile_data.append(tile_data2)
    #tile_data_iterator[0] = itertools.cycle(tile_data)


    #current_set = tile_data1

    #print(f'read bin files 1: {len(tile_data1)}, 2: {len(tile_data2)}')
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("", 9090), RelayTCPHandler) as server:
    # with socketserver.ThreadingTCPServer(("192.168.86.133", 9090), TestTCPHandler) as server:
    # with socketserver.TCPServer(("127.0.0.1", 9090), TestTCPHandler) as server:
        server.daemon_threads = True
        server.serve_forever()
    pass

if __name__ == '__main__':
    main()
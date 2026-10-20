"""The handwriting recognizer: a small CNN reads the 48-px line image into 3 × (W/4) cells of 192
channels, two bidirectional LSTMs read the columns left to right and right to left, and a linear layer
gives each column's character scores for CTC (output 0 is the blank)."""
import torch
from torch import nn

POOLS = {0: (2, 2), 1: (2, 2), 3: (2, 1), 5: (2, 1)}  # after which conv
CHANNELS = [1, 32, 64, 128, 128, 192, 192]
HIDDEN = 160


class CRNN(nn.Module):
    def __init__(self, num_classes):
        super().__init__()
        layers = []
        for i in range(6):
            layers += [nn.Conv2d(CHANNELS[i], CHANNELS[i + 1], 3, padding=1, bias=False),
                       nn.BatchNorm2d(CHANNELS[i + 1]), nn.ReLU(inplace=True)]
            if i in POOLS:
                layers.append(nn.MaxPool2d(POOLS[i], POOLS[i]))
        self.cnn = nn.Sequential(*layers)
        self.rnn1 = nn.LSTM(CHANNELS[-1] * 3, HIDDEN, bidirectional=True, batch_first=True)
        self.rnn2 = nn.LSTM(HIDDEN * 2, HIDDEN, bidirectional=True, batch_first=True)
        self.fc = nn.Linear(HIDDEN * 2, num_classes)

    def forward(self, x):
        """x: [B, 1, 48, W] ink 1 on 0 → logits [B, W/4, classes]."""
        f = self.cnn(x)
        b, c, h, w = f.shape
        f = f.permute(0, 3, 1, 2).reshape(b, w, c * h)  # feature index = channel × 3 + row
        f, _ = self.rnn1(f)
        f, _ = self.rnn2(f)
        return self.fc(f)


def convs(model):
    return [m for m in model.cnn if isinstance(m, nn.Conv2d)]


def norms(model):
    return [m for m in model.cnn if isinstance(m, nn.BatchNorm2d)]

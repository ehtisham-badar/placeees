-- Voice drops: the recording's loudness envelope, so playback can show its real shape.
ALTER TABLE drops ADD COLUMN waveform REAL[] CHECK (waveform IS NULL OR cardinality(waveform) <= 64);

cd Sources
xcrun -sdk macosx metal -o Metal/add.ir -c Metal/add.metal
xcrun -sdk macosx metallib -o Metal/default.metallib Metal/add.ir

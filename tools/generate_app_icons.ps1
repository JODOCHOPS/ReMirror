param(
    [string]$Source = (Join-Path $PSScriptRoot '..\assets\icon\app_icon.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)

function New-IconPngBytes {
    param([System.Drawing.Image]$Image, [int]$Size)

    $bitmap = [System.Drawing.Bitmap]::new($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $stream = [System.IO.MemoryStream]::new()
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.DrawImage($Image, [System.Drawing.Rectangle]::new(0, 0, $Size, $Size))
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    }
    finally {
        $stream.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

try {
    if ($sourceImage.Width -ne $sourceImage.Height) {
        throw 'The source app icon must be square.'
    }

    $androidSizes = [ordered]@{
        mdpi = 48
        hdpi = 72
        xhdpi = 96
        xxhdpi = 144
        xxxhdpi = 192
    }
    foreach ($density in $androidSizes.Keys) {
        $path = Join-Path $root "android\app\src\main\res\mipmap-$density\ic_launcher.png"
        [System.IO.File]::WriteAllBytes($path, (New-IconPngBytes -Image $sourceImage -Size $androidSizes[$density]))
    }

    $windowsSizes = @(16, 24, 32, 48, 64, 128, 256)
    $pngImages = [System.Collections.Generic.List[byte[]]]::new()
    foreach ($size in $windowsSizes) {
        $pngImages.Add((New-IconPngBytes -Image $sourceImage -Size $size))
    }
    $path = Join-Path $root 'windows\runner\resources\app_icon.ico'
    $file = [System.IO.File]::Create($path)
    $writer = [System.IO.BinaryWriter]::new($file)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$windowsSizes.Count)
        $offset = 6 + 16 * $windowsSizes.Count
        for ($i = 0; $i -lt $windowsSizes.Count; $i++) {
            $size = $windowsSizes[$i]
            $writer.Write([byte]($size % 256))
            $writer.Write([byte]($size % 256))
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$pngImages[$i].Length)
            $writer.Write([uint32]$offset)
            $offset += $pngImages[$i].Length
        }
        foreach ($png in $pngImages) {
            $writer.Write([byte[]]$png)
        }
    }
    finally {
        $writer.Dispose()
    }
}
finally {
    $sourceImage.Dispose()
}

import os
import uuid
from io import BytesIO
from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, RedirectResponse
from PIL import Image

router = APIRouter(prefix='/images', tags=['images'])

UPLOAD_DIR = Path(__file__).resolve().parents[2] / 'uploads'
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
MAX_IMAGE_BYTES = 8 * 1024 * 1024
ALLOWED_FORMATS = {'JPEG', 'PNG', 'WEBP'}


def _prepare_image(raw: bytes) -> bytes:
    if len(raw) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail='圖片檔案過大')
    try:
        image = Image.open(BytesIO(raw))
        if image.format not in ALLOWED_FORMATS:
            raise HTTPException(status_code=400, detail='不支援的圖片格式')
        if image.mode != 'RGB':
            image = image.convert('RGB')
        image.thumbnail((1600, 1600), Image.Resampling.LANCZOS)
        output = BytesIO()
        image.save(output, format='WEBP', quality=85, optimize=True)
        return output.getvalue()
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=400, detail=f'無效圖片: {error}')


def _cloudinary_enabled() -> bool:
    return bool(os.getenv('CLOUDINARY_URL')) and os.getenv('USE_CLOUD_STORAGE', 'false').lower() == 'true'


@router.post('/upload')
async def upload_image(file: UploadFile = File(...)):
    raw = await file.read()
    prepared = _prepare_image(raw)
    image_id = uuid.uuid4().hex

    if _cloudinary_enabled():
        from cloudinary import uploader

        uploader.upload(
            BytesIO(prepared),
            public_id=f'chat_{image_id}',
            resource_type='image',
            format='webp',
            overwrite=True,
        )
    else:
        (UPLOAD_DIR / f'{image_id}.webp').write_bytes(prepared)

    return {'image_id': image_id}


@router.get('/{image_id}')
def get_image(image_id: str):
    if not image_id.isalnum():
        raise HTTPException(status_code=400, detail='無效圖片 ID')

    if _cloudinary_enabled():
        import cloudinary.utils

        url, _ = cloudinary.utils.cloudinary_url(
            f'chat_{image_id}',
            format='webp',
            secure=True,
        )
        return RedirectResponse(url=url)

    path = UPLOAD_DIR / f'{image_id}.webp'
    if not path.exists():
        raise HTTPException(status_code=404, detail='圖片不存在')
    return FileResponse(path, media_type='image/webp')

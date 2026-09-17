import base64
import logging
import os
import uuid
from io import BytesIO

from PIL import Image

logger = logging.getLogger(__name__)


class CloudAvatarService:
    max_size = 1024
    max_file_size = 5 * 1024 * 1024
    allowed_formats = {'JPEG', 'PNG', 'WEBP'}

    def __init__(self) -> None:
        self.enabled = os.getenv('USE_CLOUD_STORAGE', 'false').lower() == 'true'
        self.cloudinary_url = os.getenv('CLOUDINARY_URL')

        if self.enabled and self.cloudinary_url:
            import cloudinary

            cloudinary.config(cloudinary_url=self.cloudinary_url)

    def _decode(self, value: str) -> Image.Image:
        if value.startswith('data:image'):
            value = value.split(',', 1)[1]
        raw = base64.b64decode(value)
        if len(raw) > self.max_file_size:
            raise ValueError('圖片檔案過大')

        image = Image.open(BytesIO(raw))
        if image.format not in self.allowed_formats:
            raise ValueError(f'不支援的圖片格式: {image.format}')
        return image

    def _prepare(self, image: Image.Image) -> BytesIO:
        if image.mode != 'RGB':
            image = image.convert('RGB')
        image.thumbnail((self.max_size, self.max_size), Image.Resampling.LANCZOS)

        output = BytesIO()
        image.save(output, format='WEBP', quality=85, optimize=True)
        output.seek(0)
        return output

    def save_avatar(self, avatar_base64: str, user_id: int, request_url: str | None = None) -> str:
        if not self.enabled or not self.cloudinary_url:
            raise ValueError('雲端頭像儲存尚未設定')

        from cloudinary import uploader

        image = self._prepare(self._decode(avatar_base64))
        public_id = f'avatars/user_{user_id}_{uuid.uuid4().hex[:8]}'
        result = uploader.upload(
            image,
            public_id=public_id,
            resource_type='image',
            format='webp',
            overwrite=True,
            invalidate=True,
        )
        return result['secure_url']

    def delete_avatar(self, avatar_url: str) -> bool:
        if not self.enabled or 'cloudinary' not in avatar_url:
            return False

        try:
            from cloudinary import uploader

            parts = avatar_url.split('/')
            index = parts.index('avatars')
            filename = parts[index + 1].split('.')[0]
            result = uploader.destroy(f'avatars/{filename}')
            return result.get('result') == 'ok'
        except Exception:
            logger.exception('Failed to delete avatar')
            return False


cloud_avatar_service = CloudAvatarService()

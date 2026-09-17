import asyncio
import json
import os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix='/ai', tags=['ai'])


class GenerateRequest(BaseModel):
    message: str
    context: str | None = None
    personality: str = 'default'
    roomId: str | None = None


class SummaryRequest(BaseModel):
    messages: list[str]


class EmotionRequest(BaseModel):
    message: str


PERSONALITIES = {
    'default': '你是一個友善、樂於助人的 AI 助手。請用繁體中文回應，保持簡潔而有用。',
    'funny': '你是一個幽默風趣但仍然有幫助的 AI 助手。請用繁體中文回應。',
    'professional': '你是一個專業、正式的 AI 助手。請用繁體中文提供準確清楚的資訊。',
    'casual': '你是一個輕鬆自然、像朋友一樣聊天的 AI 助手。請用繁體中文回應。',
}


def _generate(prompt: str) -> str:
    api_key = os.getenv('GEMINI_API_KEY')
    if not api_key:
        raise HTTPException(status_code=503, detail='GEMINI_API_KEY is not configured')

    model = os.getenv('GEMINI_MODEL', 'gemini-2.0-flash')
    endpoint = (
        f'https://generativelanguage.googleapis.com/v1beta/models/'
        f'{model}:generateContent?key={api_key}'
    )
    payload = json.dumps(
        {
            'contents': [{'parts': [{'text': prompt}]}],
            'generationConfig': {
                'temperature': 0.7,
                'topP': 0.95,
                'maxOutputTokens': 1024,
            },
        }
    ).encode('utf-8')

    request = Request(
        endpoint,
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )

    try:
        with urlopen(request, timeout=30) as response:
            result = json.loads(response.read().decode('utf-8'))
    except HTTPError as error:
        detail = error.read().decode('utf-8', errors='replace')
        raise HTTPException(status_code=502, detail=f'Gemini API error: {detail[:500]}')
    except (URLError, TimeoutError) as error:
        raise HTTPException(status_code=502, detail=f'Gemini connection failed: {error}')

    try:
        return result['candidates'][0]['content']['parts'][0]['text']
    except (KeyError, IndexError, TypeError):
        raise HTTPException(status_code=502, detail='Gemini returned an unexpected response')


@router.post('/generate')
async def generate(payload: GenerateRequest):
    personality = PERSONALITIES.get(payload.personality, PERSONALITIES['default'])
    sections = [personality]
    if payload.context:
        sections.append(f'聊天室上下文：\n{payload.context}')
    sections.append(f'用戶訊息：{payload.message}')
    response = await asyncio.to_thread(_generate, '\n\n'.join(sections))
    return {'response': response}


@router.post('/summarize')
async def summarize(payload: SummaryRequest):
    prompt = '請用繁體中文簡潔總結以下對話：\n\n' + '\n'.join(payload.messages)
    return {'summary': await asyncio.to_thread(_generate, prompt)}


@router.post('/emotion')
async def emotion(payload: EmotionRequest):
    prompt = (
        '請分析以下訊息的情緒，以「正面 / 負面 / 中性」其中一類加上一個 emoji '
        '和一句簡短說明回應：\n\n' + payload.message
    )
    return {'emotion': await asyncio.to_thread(_generate, prompt)}

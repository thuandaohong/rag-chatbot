"""
Test cho handler.py — chạy offline, KHÔNG gọi AWS thật.
Chỉ test logic thuần (validate input, format response).
pytest tự tìm file test_*.py.
"""
import json
import os

# handler.py đọc KB_ID lúc import -> set env giả trước khi import
os.environ.setdefault("KB_ID", "TEST_KB")

import handler


def test_thieu_question_tra_ve_400():
    event = {"body": json.dumps({})}
    resp = handler.lambda_handler(event, None)
    assert resp["statusCode"] == 400


def test_body_khong_phai_json_tra_ve_400():
    event = {"body": "khong-phai-json"}
    resp = handler.lambda_handler(event, None)
    assert resp["statusCode"] == 400


def test_response_dung_dinh_dang():
    resp = handler._response(200, {"ok": True})
    assert resp["statusCode"] == 200
    assert resp["headers"]["Content-Type"] == "application/json"
    assert json.loads(resp["body"]) == {"ok": True}

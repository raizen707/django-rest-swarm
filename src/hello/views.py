
from django.http import JsonResponse
from rest_framework.response import Response
from rest_framework.views import APIView

class HealthView(APIView):
    def get(self, request):
        return JsonResponse({"status": "ok"})

class HelloView(APIView):
    def get(self, request):
        return JsonResponse({"message": "Hello, world! from Django REST Framework"})

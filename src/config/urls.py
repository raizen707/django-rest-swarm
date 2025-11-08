from django.urls import path
from hello.views import HealthView, HelloView

urlpatterns = [
    path("health/", HealthView.as_view()),
    path("hello/", HelloView.as_view()),
]


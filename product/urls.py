from django.contrib import admin
from django.urls import path
from rest_framework import routers
from rest_framework.authtoken.views import obtain_auth_token
from rest_framework_simplejwt.views import TokenObtainPairView,TokenRefreshView,TokenVerifyView

from .views import *

urlpatterns = [
    path('admin/', admin.site.urls),
#     path('',current_datetime),

    path('payment_type/', payment_typeView.as_view()),
    path('payment_bank/', payment_banksView.as_view()),
    path('payment_name/', payment_nameView.as_view()),
    path('transaction_payment/',payment_createView.as_view()),
    path('paymenttype/', paymenttype_View.as_view()),
    
#    //auth api
    path('gettoken/',TokenObtainPairView.as_view()),
    path('refreshtoken/', TokenRefreshView.as_view()),

    # product api start
     path('categoris/', CategorisView.as_view()),
    path('product-unit/', UnitisView.as_view()),
    path('product-subcategories/', SubcategorisView.as_view()),
    path('products/', ProductisView.as_view()),
    path('createproducts/', CreateProductisView.as_view()),
    path('deleteproducts/',deleteproductView.as_view()),
    path('updateproducts/', UpdateProductisView.as_view()),


]
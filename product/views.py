from django.shortcuts import render
from django.http import HttpResponse
import datetime

from urllib import response
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.authentication import TokenAuthentication
from rest_framework_simplejwt.authentication import JWTAuthentication
from django.db.models import Q
from django.utils import timezone
from .models import *
from .serializers import *
from django.contrib.auth.models import User
from django.db.models import Q
from django.utils import timezone
from django.contrib.auth.models import User

def current_datetime(request):
    now = datetime.datetime.now()
    html = "<html><body>It is now %s.</body></html>" % now
    return HttpResponse(html)

class payment_typeView(APIView):
    authentication_classes=[JWTAuthentication, ]
    # permission_classes = [IsAuthenticated, ]

    def get(self, request):
        payment_obj = Payment_type.objects.all()
        payment_serializer = PaymentSerializer(
            payment_obj, many=True).data
        return Response(payment_serializer)

class payment_banksView(APIView):
    def get(self,request):
        product_bank=payment_bank.objects.all()
        prodbank_serializers=payment_bankSerializers(product_bank,many=True).data
        return Response(prodbank_serializers)
class payment_nameView(APIView):
    def get(self,request):
        payment_nmeobj=payment_name.objects.all()
        prodname_serializers=payment_nameSerializers(payment_nmeobj,many=True).data
        return Response(prodname_serializers)




class paymenttype_View(APIView):
    def get(self,request):
        paymenttype_obj=Payment_type.objects.all()
        paymenttype_serializers=PaymentSerializer(paymenttype_obj,many=True).data
        return Response(paymenttype_serializers)


# ///payment views
class payment_createView(APIView):
    def post(self,request):
        payment_obj = Payment_type()
        payment_obj.payment_id=request.data['payment_id']
        payment_obj.payment_type=request.data['payment_type']
        payment_obj.payment_amount=request.data['payment_amount']
        payment_obj.check_bank=request.data['check_bank']
        payment_obj.deposite_date=request.data['deposite_date']
        payment_obj.reference_no=request.data['reference_no']
        payment_obj.bank_account=request.data['bank_account']
        payment_obj.save()
        response_data={'error':'false','message':'something wrong !!!'}
        return Response(response_data)


# //product view start
class CategorisView(APIView):
    def get(self, request):
        categoris_obj = Ecom_item_type.objects.all()
        category_serializer = sellItemSerializers(
            categoris_obj, many=True).data
        return Response(category_serializer)
class UnitisView(APIView):
    def get(self, request):
        unit_obj = Products_Unit.objects.all()
        unit_serializer = ProductUnitSerializer(
            unit_obj, many=True).data
        return Response(unit_serializer)

class SubcategorisView(APIView):
    def get(self, request):
        sub_cat_obj = Ecom_Product_Sub_Categories.objects.all()
        unit_serializer = sellsubcategorySerializers(
            sub_cat_obj, many=True).data
        return Response(unit_serializer)


class ProductisView(APIView):
    authentication_classes=[JWTAuthentication, ]
    # permission_classes = [IsAuthenticated, ]
    def get(self, request):
        product_obj = Ecom_Products.objects.all()
        product_serializer = ProductSerializer(
            product_obj, many=True).data
        return Response(product_serializer)


    
class CreateProductisView(APIView):
    def post(self, request):
        product = Ecom_Products()
        product.product_id=request.data['id']
        product.product_name=request.data['product_name']
        product.product_model=request.data['product_model']
        product.product_price=request.data['product_price']
        product.discount_amount=request.data['discount_amount']
        product.product_old_price=request.data['product_old_price']
        unit_obj=Products_Unit.objects.get(unit_id=request.data['unit_id'])
        product.unit_id=unit_obj
        category_obj=Ecom_item_type.objects.get(categories_id=request.data['category_id'])
        product.category_id=category_obj
        sub_category_obj=Ecom_Product_Sub_Categories.objects.get(subcategories_id=request.data['sub_category_id'])
        product.sub_category_id=sub_category_obj
        product.stock_limit=request.data['stock_limit']
        product.app_data_time=request.data['purchase_date']
        product.save()
        response_data = {"error":False,"message":"product Data is created"}
        return Response(response_data)

class UpdateProductisView(APIView):
    def post(self, request):
        product = Ecom_Products.objects.get(product_id=request.data['product_id'])
        product.product_name=request.data['product_name'] 
        product.product_model=request.data['product_model']
        product.product_price=request.data['product_price']
        product.discount_amount=request.data['discount_amount']
        product.product_old_price=request.data['product_old_price']
        unit_obj=Products_Unit.objects.get(unit_id=request.data['unit_id'])
        product.unit_id=unit_obj
        category_obj=Ecom_item_type.objects.get(categories_id=request.data['category_id'])
        product.category_id=category_obj
        sub_category_obj=Ecom_Product_Sub_Categories.objects.get(subcategories_id=request.data['sub_category_id'])
        product.sub_category_id=sub_category_obj
        product.stock_limit=request.data['stock_limit']
        product.save()
        response_data = {"error":False,"message":"product Data is Updated"}
        return Response(response_data)



class deleteproductView(APIView):
    def post(self, request):
        print(request.data['id'],'kiiiiiiiiiiii')
        data={}
        Ecom_Products.objects.get(product_id=request.data['id']).delete()
        data['success_message']='delete product successfully'
        return Response(data)
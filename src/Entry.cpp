#include "Entry.h"


#include <stdio.h>
#include <direct.h>
#include <iostream>
#include "HairBase.h"
#include "EmulationSimulatedHair.h"
#include "EmulationSimulation.h"
#include "SplitSimulatedHair.h"
#include "SplitSimulation.h"


Entry::Entry(HINSTANCE hInstance) : D3DApp(hInstance)
{
	char path[FILENAME_MAX];
	_getcwd(path, sizeof(path));
	path[sizeof(path) - 1] = '\0';
	std::cout << path << std::endl;
}

Entry::~Entry()
{
}

struct MatrixBufferType
{
	XMMATRIX world;
	XMMATRIX view;
	XMMATRIX proj;
};


struct VertexData {
	XMFLOAT3 pos;
	XMFLOAT4 color;
};


bool Entry::Init()
{
	if (!D3DApp::Init())
	{
		return false;
	}
	
	//EmulationSimulation* emuSim = new EmulationSimulation(md3dDevice, md3dImmediateContext, { true, false, false, true }, (XMFLOAT4)Colors::Red, EmulationSimulation::Configuration::Z31Points);
	//EmulationSimulation* emuSim = new EmulationSimulation(md3dDevice, md3dImmediateContext, { true, false, false, true }, (XMFLOAT4)Colors::Red, EmulationSimulation::Configuration::Random);
	//EmulationSimulation* emuSim = new EmulationSimulation(md3dDevice, md3dImmediateContext, { true, false, false, true }, (XMFLOAT4)Colors::Red, EmulationSimulation::Configuration::Z12Points);
	//mRenderItems.push_back(new EmulationSimulatedHair(md3dDevice, md3dImmediateContext, emuSim));
	
	
	//SplitSimulation* splitSim = new SplitSimulation(md3dDevice, md3dImmediateContext, { true, false, false, true }, (XMFLOAT4)Colors::Red, SplitSimulation::Configuration::Z12Points);
	SplitSimulation* splitSim = new SplitSimulation(md3dDevice, md3dImmediateContext, { true, false, false, true }, (XMFLOAT4)Colors::Red, SplitSimulation::Configuration::LoadHair);
	mRenderItems.push_back(new SplitSimulatedHair(md3dDevice, md3dImmediateContext, splitSim));
	
	
	mRenderItems.push_back(new HairBase(md3dDevice));

	return true;
}

void Entry::OnResize()
{
	D3DApp::OnResize();
}

void Entry::UpdateScene(float dt)
{
	float x = mRadius * sinf(mPhi)*cosf(mTheta);
	float y = mRadius * cosf(mPhi);
	float z = mRadius * sinf(mPhi)*sinf(mTheta);

	mView = XMMatrixLookAtLH(XMVectorSet(x, y, z, 1.0f), XMVectorZero(), XMVectorSet(0.0f, 1.0f, 0.0f, 0.0f));
	mProj = XMMatrixPerspectiveFovLH(0.25f * MathHelper::Pi, AspectRatio(), 0.1f, 1000.0f);
}


void Entry::OnMouseDown(WPARAM btnState, int x, int y)
{
	mLastMousePos.x = x;
	mLastMousePos.y = y;

	SetCapture(mhMainWnd);
}

void Entry::OnMouseUp(WPARAM btnState, int x, int y)
{
	ReleaseCapture();
}

void Entry::OnMouseMove(WPARAM btnState, int x, int y)
{
	if ((btnState & MK_LBUTTON) != 0)
	{
		// Make each pixel correspond to a quarter of a degree.
		float dx = XMConvertToRadians(0.25f*static_cast<float>(x - mLastMousePos.x));
		float dy = XMConvertToRadians(0.25f*static_cast<float>(y - mLastMousePos.y));

		// Update angles based on input to orbit camera around box.
		mTheta += dx;
		mPhi += dy;

		// Restrict the angle mPhi.
		mPhi = MathHelper::Clamp(mPhi, 0.1f, MathHelper::Pi - 0.1f);
	}
	else if ((btnState & MK_RBUTTON) != 0)
	{
		// Make each pixel correspond to 0.005 unit in the scene.
		float dx = 0.005f*static_cast<float>(x - mLastMousePos.x);
		float dy = 0.005f*static_cast<float>(y - mLastMousePos.y);

		// Update the camera radius based on input.
		mRadius += dx - dy;

		// Restrict the radius.
		mRadius = MathHelper::Clamp(mRadius, 0.1f, 15.0f);
	}

	mLastMousePos.x = x;
	mLastMousePos.y = y;
}


void Entry::DrawScene()
{
	md3dImmediateContext->ClearRenderTargetView(mRenderTargetView,
		reinterpret_cast<const float*>(&Colors::Black));

	md3dImmediateContext->ClearDepthStencilView(mDepthStencilView,
		D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 1.0f, 0);

	for (int i = 0; i < mRenderItems.size(); i++)
	{
		mRenderItems[i]->UpdateCamera(md3dImmediateContext, mView, mProj);
		mRenderItems[i]->Draw(mTimer.DeltaTime(), md3dImmediateContext);
	}

	//Enable/Disable FrameCap
	//HR(mSwapChain->Present(0, 0)); //Enabled
	HR(mSwapChain->Present(1, 0)); //Disabled (1 - 4 are the steps. 1 == maxFrameRate of Monitor)
}
